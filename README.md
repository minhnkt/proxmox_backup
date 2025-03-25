- Tạo mới file proxmox_backup.sh và paste toàn bộ nội dung:
#nano proxmox_backup.sh
- CHMOD +x cho file proxmox_backup.sh
  #chmod +x proxmox_backup.sh
- Chạy script bằng lệnh ./proxmox_backup.sh

Chọn chức năng:
1) Sao lưu cấu hình Proxmox
2) Khôi phục cấu hình Proxmox
3) Upload lên Cloud Storage
4) Sao lưu LXC/VM trực tiếp lên Cloud Storage
5) Exit

-----------
Những gì được sao lưu trong "Sao lưu cấu hình Proxmox"
Cấu hình Proxmox chính (/etc/pve):
Thư mục /etc/pve chứa các tệp cấu hình liên quan đến cụm (cluster), LXC, VM, và các thiết lập quản lý khác của Proxmox.
Được nén thành tệp pve.tar trong thư mục tạm (TEMP_DIR).
Cấu hình mạng (/etc/network/interfaces, /etc/hosts, /etc/hostname, /etc/resolv.conf):
Các tệp cấu hình mạng cơ bản của hệ thống, bao gồm:
/etc/network/interfaces: Cấu hình giao diện mạng (ví dụ: bridge, VLAN, IP).
/etc/hosts: Danh sách ánh xạ tên máy chủ với địa chỉ IP.
/etc/hostname: Tên máy chủ của hệ thống.
/etc/resolv.conf: Cấu hình DNS.
Được nén thành tệp network.tar.
Thư mục gốc của người dùng root (/root/):
Sao lưu toàn bộ thư mục /root/ (thư mục gốc của người dùng root), bao gồm các tệp cấu hình cá nhân, khóa SSH (nếu có), hoặc các script tùy chỉnh.
Sử dụng tùy chọn --one-file-system để chỉ sao lưu trong cùng hệ thống tệp, tránh bao gồm các thư mục gắn ngoài.
Được nén thành tệp root.tar.
Thư mục /var/lib/ (tùy chọn đầy đủ hoặc loại trừ):
Người dùng được hỏi: "Bạn muốn sao lưu đầy đủ /var/lib/ (không loại trừ) không? (y/N, mặc định là N)".
Nếu chọn "y" (có):
Sao lưu toàn bộ /var/lib/, bao gồm dữ liệu của các dịch vụ như pve-cluster, vz (LXC), hoặc các dịch vụ khác (nếu có).
Được nén thành varlib.tar.
Nếu chọn "N" (mặc định):
Chỉ sao lưu các thư mục liên quan trực tiếp đến Proxmox:
/var/lib/pve: Dữ liệu cấu hình của Proxmox.
/var/lib/pve-cluster: Dữ liệu cụm (nếu Proxmox chạy trong cụm).
Loại trừ:
/var/lib/vz: Dữ liệu thực tế của LXC/VM (rất lớn, thường được xử lý riêng bằng vzdump trong chức năng khác).
/var/lib/docker: Dữ liệu Docker (nếu cài đặt).
/var/lib/mysql: Cơ sở dữ liệu MySQL (nếu có).
Được nén thành varlib.tar.
Thư mục spool (/var/spool/):
Sao lưu thư mục /var/spool/, chứa dữ liệu tạm thời như hàng đợi email hoặc công việc in ấn (nếu có).
Được nén thành spool.tar.
Quy trình sao lưu
Các tệp tạm (pve.tar, network.tar, root.tar, varlib.tar, spool.tar) được tạo trong thư mục tạm (TEMP_DIR).
Sau đó, tất cả các tệp .tar này được nén lại thành một tệp duy nhất:
Tên tệp: backup_${HOSTNAME}_${TIMESTAMP}_v${VERSION}.tar.gz.
Ví dụ: backup_proxmox1_20250325_123456_v8.3.5.tar.gz.
Tệp cuối cùng được lưu trong $CONFIG_BACKUP_DIR (mặc định: /backup/proxmox_configs/PROXMOX_CONFIG_BACKUP).
Báo cáo sau khi sao lưu
Báo cáo sẽ hiển thị:

Tên tệp sao lưu.
Dung lượng tệp.
Thời gian thực hiện.
Số lượng tệp sao lưu hiện có trong thư mục.
3 tệp/thư mục gốc lớn nhất (dựa trên du -h của các đường dẫn đã sao lưu).
Ví dụ:
+------------------------------------------+
| Báo cáo sao lưu cấu hình Proxmox         |
+------------------------------------------+
| Trạng thái: Hoàn tất                     |
| Tên file: /backup/proxmox_configs/PROXMOX_CONFIG_BACKUP/backup_proxmox1_20250325_123456_v8.3.5.tar.gz |
| Dung lượng: 50M                          |
| Thời gian chạy: 10 giây                  |
| Số file sao lưu hiện có: 3               |
| 3 file lớn nhất (đường dẫn gốc):         |
| /var/lib/pve (20M)                       |
| /root/ (15M)                             |
| /etc/pve (10M)                           |
+------------------------------------------+
Lưu ý
Không bao gồm dữ liệu LXC/VM: Chức năng này chỉ sao lưu cấu hình, không bao gồm dữ liệu thực tế của các container LXC hoặc máy ảo VM (như ổ đĩa, snapshot). Dữ liệu đó được xử lý trong chức năng "Sao lưu LXC/VM trực tiếp lên Cloud Storage" bằng vzdump.
Tùy chỉnh: Bạn có thể thay đổi $BACKUP_DIR hoặc chỉnh sửa các đường dẫn sao lưu trong mã nếu cần thêm/bớt thư mục.
Kích thước: Nếu chọn sao lưu đầy đủ /var/lib/, tệp sao lưu có thể rất lớn tùy thuộc vào dữ liệu trên hệ thống.

######################
Chức năng khôi phục cấu hình proxmox :
+-------------------------------------------------+
| ĐẢM BẢO FILE SAO LƯU ĐÃ ĐƯỢC ĐẶT TRONG         |
| /backup/proxmox_configs/PROXMOX_CONFIG_BACKUP TRƯỚC KHI KHÔI PHỤC!        |
+-------------------------------------------------+

######################
Chức năng Upload lên Cloud Storage:
Cần cài đặt rclone và cấu hình các cloud storage trước.
Script sẽ upload các file cấu hình ở mục 1 lên Cloud Storage

######################
Chức năng Sao lưu LXC/VM trực tiếp lên Cloud Storage
Sử dụng để backup và upload trực tiếp lên Cloud Storage, không sử dụng ổ cứng local, dùng trong trường hợp cần backup LXC/VM có dung lượng lớn, cao hơn phần còn trống của ổ cứng Local.
Có 2 chế độ sao lưu như sau:

Chọn chế độ sao lưu:
1) Sao lưu một LXC/VM
2) Sao lưu tất cả (có thể loại trừ)

Đối với chế độ thứ 2, script sẽ scan và hiển thị toàn bộ các LXC/VM đang có trên máy chủ proxmox, lựa chọn các máy chủ cần loại trừ (không sao lưu) bằng cách bấm chọn số thứ tự, kết thúc bằng phím Ctrl +D
