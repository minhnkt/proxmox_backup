#!/bin/bash

echo "LANG=en_US.UTF-8" | tee -a /etc/environment
echo "LC_ALL=en_US.UTF-8" | tee -a /etc/environment
echo "LC_CTYPE=en_US.UTF-8" | tee -a /etc/environment
echo "LANGUAGE=en_US.UTF-8" | tee -a /etc/environment
source /etc/environment

# Thư mục lưu trữ file sao lưu
BACKUP_DIR="/backup/proxmox_configs"  # Thay đổi đường dẫn theo nhu cầu
CONFIG_BACKUP_DIR="$BACKUP_DIR/PROXMOX_CONFIG_BACKUP"
VM_BACKUP_DIR="$BACKUP_DIR/VM_BACKUP"
mkdir -p "$CONFIG_BACKUP_DIR" "$VM_BACKUP_DIR"

# Biến toàn cục để lưu báo cáo cuối cùng
LAST_REPORT=""

# Hàm chạy spinner trong nền
spinner() {
    local spinners=('/' '|' '-' '\')
    while true; do
        for s in "${spinners[@]}"; do
            printf "Đang xử lý %s\r" "$s"
            sleep 0.2
        done
    done
}

# Hàm sao lưu cấu hình
backup_function() {
    local start_time=$(date +%s)
    local tasks=5
    local progress=0

    VERSION=$(pveversion | cut -d'/' -f2 | cut -d'-' -f1)
    if [ -z "$VERSION" ]; then
        echo -e "\nLỗi: Không thể lấy phiên bản Proxmox."
        LAST_REPORT="Lỗi: Không thể lấy phiên bản Proxmox."
        return 1
    fi

    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    HOSTNAME=$(hostname)
    FILENAME_FINAL="$CONFIG_BACKUP_DIR/backup_${HOSTNAME}_${TIMESTAMP}_v${VERSION}.tar.gz"

    read -p "Bạn muốn sao lưu đầy đủ /var/lib/ (không loại trừ) không? (y/N, mặc định là N): " full_backup
    full_backup=${full_backup:-N}

    spinner &
    SPINNER_PID=$!

    TEMP_DIR=$(mktemp -d /var/tmp/backup-XXXXXXXX)
    tar -cvPf "$TEMP_DIR/pve.tar" /etc/pve >/dev/null 2>&1 && progress=$((progress + 1))
    tar -cvPf "$TEMP_DIR/network.tar" /etc/network/interfaces /etc/hosts /etc/hostname /etc/resolv.conf >/dev/null 2>&1 && progress=$((progress + 1))
    tar -cvPf "$TEMP_DIR/root.tar" --one-file-system /root/ >/dev/null 2>&1 && progress=$((progress + 1))

    if [ "$full_backup" = "y" ] || [ "$full_backup" = "Y" ]; then
        echo "Sao lưu đầy đủ /var/lib/..."
        tar -cvPf "$TEMP_DIR/varlib.tar" /var/lib/ >/dev/null 2>&1 && progress=$((progress + 1))
    else
        echo "Sao lưu /var/lib/ với loại trừ..."
        tar -cvPf "$TEMP_DIR/varlib.tar" /var/lib/pve /var/lib/pve-cluster --exclude=/var/lib/vz --exclude=/var/lib/docker --exclude=/var/lib/mysql >/dev/null 2>&1 && progress=$((progress + 1))
    fi

    tar -cvPf "$TEMP_DIR/spool.tar" /var/spool/ >/dev/null 2>&1 && progress=$((progress + 1))

    top_files=$(du -h /etc/pve /etc/network/interfaces /root/ /var/lib/pve /var/lib/pve-cluster /var/spool/ 2>/dev/null | sort -hr | head -n 3 | awk '{print $2 " (" $1 ")"}')
    tar -cvzPf "$FILENAME_FINAL" "$TEMP_DIR"/*.tar >/dev/null 2>&1

    kill $SPINNER_PID >/dev/null 2>&1
    wait $SPINNER_PID 2>/dev/null
    rm -rf "$TEMP_DIR"

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local file_size=$(du -h "$FILENAME_FINAL" | cut -f1)
    local num_backups=$(ls -1 "$CONFIG_BACKUP_DIR"/*.tar.gz 2>/dev/null | wc -l)

    local time_display
    if [ "$duration" -gt 60 ]; then
        local minutes=$((duration / 60))
        local seconds=$((duration % 60))
        time_display="$minutes phút $seconds giây"
    else
        time_display="$duration giây"
    fi

    LAST_REPORT=$(cat <<EOF
+------------------------------------------+
| Báo cáo sao lưu cấu hình Proxmox         |
+------------------------------------------+
| Trạng thái: Hoàn tất                     |
| Tên file: $FILENAME_FINAL                |
| Dung lượng: $file_size                   |
| Thời gian chạy: $time_display            |
| Số file sao lưu hiện có: $num_backups    |
| 3 file lớn nhất (đường dẫn gốc):         |
| $top_files                               |
+------------------------------------------+
EOF
    )
    echo -e "\n$LAST_REPORT"
}

# Hàm khôi phục
restore_function() {
    local start_time=$(date +%s)

    echo -e "$(tput setaf 1)$(tput blink)+-------------------------------------------------+" # Màu đỏ + nhấp nháy
    echo -e "| ĐẢM BẢO FILE SAO LƯU ĐÃ ĐƯỢC ĐẶT TRONG         |"
    echo -e "| $CONFIG_BACKUP_DIR TRƯỚC KHI KHÔI PHỤC!        |"
    echo -e "+-------------------------------------------------+$(tput sgr0)"
    sleep 3
    echo -e "\033[4A$(tput setaf 1)+-------------------------------------------------+" # Giữ lại khung, không nhấp nháy
    echo -e "| ĐẢM BẢO FILE SAO LƯU ĐÃ ĐƯỢC ĐẶT TRONG         |"
    echo -e "| $CONFIG_BACKUP_DIR TRƯỚC KHI KHÔI PHỤC!        |"
    echo -e "+-------------------------------------------------+$(tput sgr0)"

    if [ -z "$(ls -A "$CONFIG_BACKUP_DIR"/*.tar.gz 2>/dev/null)" ]; then
        LAST_REPORT=$(cat <<EOF
+------------------------------------------+
| Báo cáo khôi phục cấu hình Proxmox       |
+------------------------------------------+
| Trạng thái: Thất bại                     |
| Lỗi: Không tìm thấy file sao lưu         |
| Đường dẫn: $CONFIG_BACKUP_DIR            |
+------------------------------------------+
EOF
        )
        echo -e "\n$LAST_REPORT"
        return 1
    fi

    echo "Danh sách file sao lưu:"
    select BACKUP_FILE in "$CONFIG_BACKUP_DIR"/*.tar.gz; do
        if [ -n "$BACKUP_FILE" ]; then
            break
        else
            echo "Lựa chọn không hợp lệ, thử lại."
        fi
    done

    spinner &
    SPINNER_PID=$!

    TEMP_DIR=$(mktemp -d /var/tmp/restore-XXXXXXXX)
    tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR" >/dev/null 2>&1

    local tar_files=("$TEMP_DIR"/*.tar)
    local total_tasks=${#tar_files[@]}
    local progress=0

    for tar_file in "${tar_files[@]}"; do
        tar -xPf "$tar_file" -C / >/dev/null 2>&1
        progress=$((progress + 1))
    done

    kill $SPINNER_PID >/dev/null 2>&1
    wait $SPINNER_PID 2>/dev/null
    rm -rf "$TEMP_DIR"

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local num_backups=$(ls -1 "$CONFIG_BACKUP_DIR"/*.tar.gz 2>/dev/null | wc -l)

    local time_display
    if [ "$duration" -gt 60 ]; then
        local minutes=$((duration / 60))
        local seconds=$((duration % 60))
        time_display="$minutes phút $seconds giây"
    else
        time_display="$duration giây"
    fi

    LAST_REPORT=$(cat <<EOF
+------------------------------------------+
| Báo cáo khôi phục cấu hình Proxmox       |
+------------------------------------------+
| Trạng thái: Hoàn tất                     |
| File khôi phục: $BACKUP_FILE             |
| Thời gian chạy: $time_display            |
| Số file sao lưu hiện có: $num_backups    |
+------------------------------------------+
EOF
    )
    echo -e "\n$LAST_REPORT"
}

# Hàm upload lên cloud
upload_function() {
    local start_time=$(date +%s)

    mapfile -t REMOTES < <(rclone listremotes | sed 's/:$//')
    if [ ${#REMOTES[@]} -eq 0 ]; then
        LAST_REPORT=$(cat <<EOF
+------------------------------------------+
| Báo cáo upload lên Cloud Storage         |
+------------------------------------------+
| Trạng thái: Thất bại                     |
| Lỗi: Không tìm thấy remote rclone        |
| Gợi ý: Chạy 'rclone config' để cấu hình |
+------------------------------------------+
EOF
        )
        echo -e "\n$LAST_REPORT"
        return 1
    fi

    echo "Danh sách cloud storage đã cấu hình trong rclone:"
    select REMOTE_NAME in "${REMOTES[@]}"; do
        if [ -n "$REMOTE_NAME" ]; then
            break
        else
            echo "Lựa chọn không hợp lệ, thử lại."
        fi
    done

    echo "Kiểm tra kết nối với $REMOTE_NAME..."
    TEMP_TEST_FILE=$(mktemp /tmp/rclone-test-XXXXXX)
    echo "Test file" > "$TEMP_TEST_FILE"
    rclone copy "$TEMP_TEST_FILE" "$REMOTE_NAME:/test" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        LAST_REPORT=$(cat <<EOF
+------------------------------------------+
| Báo cáo upload lên Cloud Storage         |
+------------------------------------------+
| Trạng thái: Thất bại                     |
| Lỗi: Không thể kết nối tới $REMOTE_NAME  |
+------------------------------------------+
EOF
        )
        rm -f "$TEMP_TEST_FILE"
        echo -e "\n$LAST_REPORT"
        return 1
    fi
    rclone delete "$REMOTE_NAME:/test" >/dev/null 2>&1
    rm -f "$TEMP_TEST_FILE"
    echo "Kết nối thành công, bắt đầu upload..."

    mapfile -t config_files < <(ls -1 "$CONFIG_BACKUP_DIR"/*.tar.gz 2>/dev/null)
    mapfile -t vm_files < <(ls -1 "$VM_BACKUP_DIR"/*.tar.gz 2>/dev/null)
    local total_tasks=$((${#config_files[@]} + ${#vm_files[@]}))

    if [ "$total_tasks" -eq 0 ]; then
        LAST_REPORT=$(cat <<EOF
+------------------------------------------+
| Báo cáo upload lên Cloud Storage         |
+------------------------------------------+
| Trạng thái: Thất bại                     |
| Lỗi: Không có file sao lưu để upload     |
+------------------------------------------+
EOF
        )
        echo -e "\n$LAST_REPORT"
        return 1
    fi

    spinner &
    SPINNER_PID=$!
    local uploaded_count=0

    for file in "${config_files[@]}"; do
        rclone copy "$file" "$REMOTE_NAME:/PROXMOX_CONFIG_BACKUP" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            ((uploaded_count++))
        fi
    done

    for file in "${vm_files[@]}"; do
        rclone copy "$file" "$REMOTE_NAME:/VM_BACKUP" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            ((uploaded_count++))
        fi
    done

    kill $SPINNER_PID >/dev/null 2>&1
    wait $SPINNER_PID 2>/dev/null

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local time_display
    if [ "$duration" -gt 60 ]; then
        local minutes=$((duration / 60))
        local seconds=$((duration % 60))
        time_display="$minutes phút $seconds giây"
    else
        time_display="$duration giây"
    fi

    if [ "$uploaded_count" -eq "$total_tasks" ]; then
        LAST_REPORT=$(cat <<EOF
+------------------------------------------+
| Báo cáo upload lên Cloud Storage         |
+------------------------------------------+
| Trạng thái: Hoàn tất                     |
| Số file cần upload: $total_tasks         |
| Số file đã upload: $uploaded_count       |
| Thời gian chạy: $time_display            |
+------------------------------------------+
EOF
        )
    else
        LAST_REPORT=$(cat <<EOF
+------------------------------------------+
| Báo cáo upload lên Cloud Storage         |
+------------------------------------------+
| Trạng thái: Thất bại                     |
| Số file cần upload: $total_tasks         |
| Số file đã upload: $uploaded_count       |
| Thời gian chạy: $time_display            |
| Lỗi: Một số file không upload được       |
+------------------------------------------+
EOF
        )
    fi
    echo -e "\n$LAST_REPORT"
}

# Hàm sao lưu LXC/VM trực tiếp lên cloud với sửa lỗi locale
backup_lxc_vm() {
    local start_time=$(date +%s)

    mapfile -t LXC_LIST < <(pct list | tail -n +2 | awk '{print $1 " (LXC - " $3 ")"}')
    mapfile -t VM_LIST < <(qm list | tail -n +2 | awk '{print $1 " (VM - " $2 ")"}')

    if [ ${#LXC_LIST[@]} -eq 0 ] && [ ${#VM_LIST[@]} -eq 0 ]; then
        LAST_REPORT=$(cat <<EOF
+------------------------------------------+
| Báo cáo sao lưu LXC/VM trực tiếp         |
+------------------------------------------+
| Trạng thái: Thất bại                     |
| Lỗi: Không tìm thấy LXC hoặc VM          |
+------------------------------------------+
EOF
        )
        echo -e "\n$LAST_REPORT"
        return 1
    fi

    mapfile -t ALL_LIST < <(printf '%s\n' "${LXC_LIST[@]}" "${VM_LIST[@]}")

    echo "Chọn chế độ sao lưu:"
    echo "1) Sao lưu một LXC/VM"
    echo "2) Sao lưu tất cả (có thể loại trừ)"
    read -p "Nhập lựa chọn (1 hoặc 2): " backup_mode

    local targets=()
    local EXCLUDED_ITEMS=()
    if [ "$backup_mode" = "1" ]; then
        echo "Danh sách LXC và VM hiện có:"
        select TARGET in "${ALL_LIST[@]}"; do
            if [ -n "$TARGET" ]; then
                targets+=("$TARGET")
                break
            else
                echo "Lựa chọn không hợp lệ, thử lại."
            fi
        done
    elif [ "$backup_mode" = "2" ]; then
        echo "Danh sách LXC và VM hiện có (chọn để loại trừ, nhập số và Enter, nhấn Ctrl+D hoặc nhập 'Xong' khi hoàn tất):"
        select EXCLUDE in "${ALL_LIST[@]}" "Xong"; do
            if [ "$EXCLUDE" = "Xong" ]; then
                break
            elif [ -n "$EXCLUDE" ]; then
                EXCLUDED_ITEMS+=("$EXCLUDE")
                echo "Đã loại trừ: $EXCLUDE"
            else
                echo "Lựa chọn không hợp lệ, thử lại."
            fi
        done

        for item in "${ALL_LIST[@]}"; do
            exclude_flag=0
            for excl in "${EXCLUDED_ITEMS[@]}"; do
                if [ "$item" = "$excl" ]; then
                    exclude_flag=1
                    break
                fi
            done
            if [ "$exclude_flag" -eq 0 ]; then
                targets+=("$item")
            fi
        done

        if [ ${#targets[@]} -eq 0 ]; then
            LAST_REPORT=$(cat <<EOF
+------------------------------------------+
| Báo cáo sao lưu LXC/VM trực tiếp         |
+------------------------------------------+
| Trạng thái: Thất bại                     |
| Lỗi: Không có LXC/VM nào để sao lưu      |
+------------------------------------------+
EOF
            )
            echo -e "\n$LAST_REPORT"
            return 1
        fi
    else
        LAST_REPORT=$(cat <<EOF
+------------------------------------------+
| Báo cáo sao lưu LXC/VM trực tiếp         |
+------------------------------------------+
| Trạng thái: Thất bại                     |
| Lỗi: Lựa chọn không hợp lệ               |
+------------------------------------------+
EOF
        )
        echo -e "\n$LAST_REPORT"
        return 1
    fi

    mapfile -t REMOTES < <(rclone listremotes | sed 's/:$//')
    if [ ${#REMOTES[@]} -eq 0 ]; then
        LAST_REPORT=$(cat <<EOF
+------------------------------------------+
| Báo cáo sao lưu LXC/VM trực tiếp         |
+------------------------------------------+
| Trạng thái: Thất bại                     |
| Lỗi: Không tìm thấy remote rclone        |
+------------------------------------------+
EOF
        )
        echo -e "\n$LAST_REPORT"
        return 1
    fi

    echo "Danh sách cloud storage đã cấu hình trong rclone:"
    select REMOTE_NAME in "${REMOTES[@]}"; do
        if [ -n "$REMOTE_NAME" ]; then
            break
        else
            echo "Lựa chọn không hợp lệ, thử lại."
        fi
    done

    echo "Kiểm tra kết nối với $REMOTE_NAME..."
    TEMP_TEST_FILE=$(mktemp /tmp/rclone-test-XXXXXX)
    echo "Test file" > "$TEMP_TEST_FILE"
    rclone copy "$TEMP_TEST_FILE" "$REMOTE_NAME:/test" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        LAST_REPORT=$(cat <<EOF
+------------------------------------------+
| Báo cáo sao lưu LXC/VM trực tiếp         |
+------------------------------------------+
| Trạng thái: Thất bại                     |
| Lỗi: Không thể kết nối tới $REMOTE_NAME  |
+------------------------------------------+
EOF
        )
        rm -f "$TEMP_TEST_FILE"
        echo -e "\n$LAST_REPORT"
        return 1
    fi
    rclone delete "$REMOTE_NAME:/test" >/dev/null 2>&1
    rm -f "$TEMP_TEST_FILE"

    local REPORT_SELECTED=""
    local REPORT_EXCLUDED=""
    local REPORT_STATUS=""
    local total_size_mb=0
    local total_duration=0
    local MAX_RETRIES=3
    local RETRY_DELAY=60

    spinner &
    SPINNER_PID=$!

    # Thiết lập locale tạm thời để tránh cảnh báo
    export LC_ALL="en_US.UTF-8"
    export LANG="en_US.UTF-8"
    export LC_CTYPE="en_US.UTF-8"

    for TARGET in "${targets[@]}"; do
        TARGET_ID=$(echo "$TARGET" | awk '{print $1}')
        TARGET_TYPE=$(echo "$TARGET" | grep -o "LXC\|VM")
        TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
        BACKUP_FILE="backup_${TARGET_TYPE}_${TARGET_ID}_${TIMESTAMP}.tar.gz"

        REPORT_SELECTED="$REPORT_SELECTED$TARGET\n"

        echo "Bắt đầu sao lưu $TARGET_TYPE $TARGET_ID trực tiếp lên $REMOTE_NAME:/VM_BACKUP/$BACKUP_FILE..."

        local target_start_time=$(date +%s)
        local error_output=""
        local exit_code=1
        local retries=0
        local file_size_mb=0
        local upload_speed=0

        while [ $retries -lt $MAX_RETRIES ] && [ $exit_code -ne 0 ]; do
            error_output=$(vzdump "$TARGET_ID" --mode snapshot --compress zstd --stdout 2>&1 | rclone rcat "$REMOTE_NAME:/VM_BACKUP/$BACKUP_FILE" 2>&1)
            exit_code=$?
            if [ $exit_code -ne 0 ] && echo "$error_output" | grep -q "RATE_LIMIT_EXCEEDED"; then
                retries=$((retries + 1))
                if [ $retries -lt $MAX_RETRIES ]; then
                    echo "Lỗi: Quota exceeded, thử lại sau $RETRY_DELAY giây (lần $retries/$MAX_RETRIES)..."
                    sleep $RETRY_DELAY
                fi
            else
                break
            fi
        done

        local target_end_time=$(date +%s)
        local target_duration=$((target_end_time - target_start_time))

        if [ $exit_code -eq 0 ] && rclone ls "$REMOTE_NAME:/VM_BACKUP/$BACKUP_FILE" >/dev/null 2>&1; then
            local file_size_bytes=$(rclone ls "$REMOTE_NAME:/VM_BACKUP/$BACKUP_FILE" | awk '{print $1}')
            file_size_mb=$(echo "scale=2; $file_size_bytes / 1024 / 1024" | bc)
            total_size_mb=$(echo "scale=2; $total_size_mb + $file_size_mb" | bc)
            total_duration=$((total_duration + target_duration))
            if [ $target_duration -gt 0 ]; then
                upload_speed=$(echo "scale=2; $file_size_mb / $target_duration" | bc)
            fi
            REPORT_STATUS="$REPORT_STATUS$TARGET_TYPE $TARGET_ID: Thành công (Dung lượng: $file_size_mb MB, Thời gian: $target_duration giây, Tốc độ: $upload_speed MB/s)\n"
        else
            if echo "$error_output" | grep -q "RATE_LIMIT_EXCEEDED"; then
                REPORT_STATUS="$REPORT_STATUS$TARGET_TYPE $TARGET_ID: Thất bại (Lỗi: Quota exceeded sau $MAX_RETRIES lần thử, xem https://cloud.google.com/docs/quotas/help/request_increase)\n"
            else
                REPORT_STATUS="$REPORT_STATUS$TARGET_TYPE $TARGET_ID: Thất bại (Lỗi: ${error_output:-Kiểm tra kết nối hoặc vzdump thất bại})\n"
            fi
        fi
    done

    kill $SPINNER_PID >/dev/null 2>&1
    wait $SPINNER_PID 2>/dev/null

    if [ ${#EXCLUDED_ITEMS[@]} -eq 0 ]; then
        REPORT_EXCLUDED="Không có\n"
    else
        for excl in "${EXCLUDED_ITEMS[@]}"; do
            REPORT_EXCLUDED="$REPORT_EXCLUDED$excl\n"
        done
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local time_display
    if [ "$duration" -gt 60 ]; then
        local minutes=$((duration / 60))
        local seconds=$((duration % 60))
        time_display="$minutes phút $seconds giây"
    else
        time_display="$duration giây"
    fi

    local avg_upload_speed
    if [ $total_duration -gt 0 ]; then
        avg_upload_speed=$(echo "scale=2; $total_size_mb / $total_duration" | bc)
    else
        avg_upload_speed="0.00"
    fi

    LAST_REPORT=$(cat <<EOF
+------------------------------------------+
| Báo cáo sao lưu LXC/VM trực tiếp         |
+------------------------------------------+
| Trạng thái: Hoàn tất                     |
| Danh sách LXC/VM đã chọn:                |
| $REPORT_SELECTED                         |
| Danh sách LXC/VM đã loại trừ:            |
| $REPORT_EXCLUDED                         |
| Chi tiết sao lưu:                        |
| $REPORT_STATUS                           |
| Tổng thời gian thực hiện: $time_display  |
| Tổng dung lượng backup: $total_size_mb MB|
| Tốc độ upload trung bình: $avg_upload_speed MB/s |
+------------------------------------------+
EOF
    )
    echo -e "\n$LAST_REPORT"
}

# Hàm hiển thị menu
show_menu() {
    while true; do
        echo "Chọn chức năng:"
        echo "1) Sao lưu cấu hình Proxmox"
        echo "2) Khôi phục cấu hình Proxmox"
        echo "3) Upload lên Cloud Storage"
        echo "4) Sao lưu LXC/VM trực tiếp lên Cloud Storage"
        echo "5) Exit"
        read -p "Nhập lựa chọn (1, 2, 3, 4 hoặc 5): " choice

        if [ -n "$LAST_REPORT" ]; then
            echo -e "\n$LAST_REPORT"
        fi

        case "$choice" in
            1) backup_function ;;
            2) restore_function ;;
            3) upload_function || { sleep 2; } ;;
            4) backup_lxc_vm ;;
            5) echo "Thoát script..."; exit 0 ;;
            *) echo "Lựa chọn không hợp lệ." ;;
        esac
    done
}

# Xử lý tham số hoặc hiển thị menu
if [ -z "$1" ]; then
    show_menu
else
    case "$1" in
        "backup") backup_function ;;
        "restore") restore_function ;;
        "upload") upload_function ;;
        "backup_lxc_vm") backup_lxc_vm ;;
        *) echo "Sử dụng: $0 {backup|restore|upload|backup_lxc_vm}" ;;
    esac
fi
