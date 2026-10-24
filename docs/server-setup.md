# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины

- Гипервизор: VirtualBox 7.2, гостевая система Ubuntu Server 24.04 LTS (64-bit), имя машины devops-vm
- Оперативная память: 2048 МБ
- Процессор: 2 ядра
- Диск: 25 ГБ, динамически расширяемый
- Имя узла: devops-vm, полное имя devops-vm.devops.local

## 2. Сетевые интерфейсы

- Адаптер 1, тип NAT, интерфейс enp0s3, адрес 10.0.2.15/24 (DHCP VirtualBox). Назначение: выход в Интернет, установка пакетов.
- Адаптер 2, тип Host-only (VirtualBox Host-Only Ethernet Adapter, сеть 192.168.56.0/24), интерфейс enp0s8, адрес 192.168.56.101/24 (DHCP VirtualBox, адрес хоста 192.168.56.1). Назначение: доступ с хостовой системы к веб-серверу и SSH.
- Сопоставление имени на хостовой системе: в файле C:\Windows\System32\drivers\etc\hosts добавлена строка `192.168.56.101   devops.local`.
- Сопоставление имени на сервере: `sudo hostnamectl set-hostname devops-vm`, затем `sudo sed -i 's/^127.0.1.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts`.

## 3. Правило проброса портов

Адаптер 1 (NAT), правило с именем ssh: протокол TCP, адрес хоста 127.0.0.1, порт хоста 2222, порт гостя 2222 (адрес гостя не заполняется). Первоначально порт гостя был 22 и после изменения порта sshd заменён на 2222. Команда: `VBoxManage modifyvm devops-vm --natpf1 "ssh,tcp,127.0.0.1,2222,,2222"`.

## 4. Учётные записи

- student: создана при установке, входит в группу sudo, аутентификация по паролю (только локальная консоль, по SSH вход запрещён директивой AllowUsers).
- devops: создана командами `sudo adduser devops` и `sudo usermod -aG sudo devops`, входит в группы devops, sudo, users. Аутентификация по SSH только по ключу ed25519: открытый ключ хоста (`ssh-keygen -t ed25519 -C "devops-vm-key" -f ~/.ssh/devops_vm`) записан в /home/devops/.ssh/authorized_keys. Права: каталог ~/.ssh 700, файл authorized_keys 600, владелец devops. Пароль нужен только для sudo.
- На хостовой системе в ~/.ssh/config описан узел devops: HostName 127.0.0.1, Port 2222, User devops, IdentityFile ~/.ssh/devops_vm, IdentitiesOnly yes.

## 5. Служба SSH

- Пакет: openssh-server. Основной файл /etc/ssh/sshd_config не изменялся, его копия сохранена в /etc/ssh/sshd_config.backup.
- Файл настроек: /etc/ssh/sshd_config.d/99-hardening.conf (права 644, владелец root). Каталог не содержит других файлов с директивой PasswordAuthentication.
- Значения директив: Port 2222, PermitRootLogin no, PasswordAuthentication no, PubkeyAuthentication yes, PermitEmptyPasswords no, MaxAuthTries 3, LoginGraceTime 30, AllowUsers devops, X11Forwarding no, ClientAliveInterval 300, ClientAliveCountMax 2.
- Активация по сокету отключена, чтобы порт брался из конфигурации: `sudo systemctl disable --now ssh.socket`, `sudo systemctl enable --now ssh.service`, `sudo systemctl restart ssh`.
- Проверка: `sudo sshd -t`, `sudo sshd -T | grep -Ei "^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers)"`, `sudo ss -tlnp | grep sshd` (ожидается 0.0.0.0:2222).

## 6. Правила межсетевого экрана

Подсистема ufw. Политики по умолчанию: входящие deny, исходящие allow. Правила создаются до активации командой `sudo ufw enable`:

```
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw logging medium
sudo ufw enable
```

Правило `ufw allow ssh` не используется: оно открывает порт 22, а не 2222. Журнал блокировок: /var/log/ufw.log.

## 7. Снимки состояния

- 01-clean-install: чистая установка Ubuntu Server 24.04 с OpenSSH, система обновлена (создан до всех настроек).
- 02-keys-configured: создана учётная запись devops, настроен вход по ключу и файл ~/.ssh/config.
- 03-ssh-hardened: применён 99-hardening.conf, порт 2222, проброс портов изменён на 2222. Снимки создаются на выключенной машине.

## 8. Веб-сервер

- Пакеты: `sudo apt install -y nginx rsync` (nginx 1.24.0 из репозитория Ubuntu 24.04). Порты 80 и 443 уже разрешены правилами из раздела 6, профиль `Nginx Full` не нужен.
- Конфигурация ресурса: /etc/nginx/sites-available/devops-site, активируется ссылкой `sudo ln -s /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/`. Стандартный ресурс отключён удалением ссылки: `sudo rm /etc/nginx/sites-enabled/default`.
- Содержимое devops-site: блок server на портах 80 и [::]:80 с server_name devops.local и `return 301 https://$host$request_uri;`; блок server на портах 443 и [::]:443 с `ssl`, server_name devops.local, `ssl_certificate /etc/ssl/certs/devops.crt`, `ssl_certificate_key /etc/ssl/private/devops.key`, `ssl_protocols TLSv1.2 TLSv1.3`, `root /var/www/devops-site`, `index index.html`, `location / { try_files $uri $uri/ =404; }`, `error_page 404 /404.html`, журналы /var/log/nginx/devops-site.access.log и /var/log/nginx/devops-site.error.log. Заголовок HSTS не добавляется.
- Применение изменений: `sudo nginx -t && sudo systemctl reload nginx` (не restart).
- Каталог ресурса: /var/www/devops-site, создан командами `sudo mkdir -p /var/www/devops-site` и `sudo chown -R devops:devops /var/www/devops-site`. Владелец devops, права каталога 755, файлов 644. Файлов с правом записи для всех быть не должно (`find /var/www/devops-site -perm -o+w` выводит пусто).
- Доставка содержимого: с хостовой системы `scripts/deploy.sh` (rsync с параметрами `-avz --delete --chmod=D755,F644`, исходный каталог site/ репозитория).
- Сертификат и ключ: /etc/ssl/certs/devops.crt (права 644, владелец root) и /etc/ssl/private/devops.key (права 600, владелец root). Ключ читает только главный процесс nginx, запущенный от root, рабочие процессы www-data его не читают и из каталога /etc/ssl/private ключ не копируется.
- Команда формирования, срок действия 365 дней, поле SAN обязательно:

```
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"
```

- Доверие на хостовой системе: `scp devops:/etc/ssl/certs/devops.crt ~/devops.crt`, затем `curl --cacert ~/devops.crt -I https://devops.local`.
- Снимок состояния: 04-nginx-https (создан после перевода ресурса на HTTPS).
