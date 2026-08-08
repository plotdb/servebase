# 設定系統

## 設定架構

### 分層設計
```
config/
├─ base/        # 範例設定（進版控）
├─ private/     # 私密設定（不進版控）
├─ gen/         # 生成的設定
└─ tool/        # 設定工具
```

### 設定類型

#### 依階段分類
- **Bootstrap** - 初始化設定（已棄用，移至 frontend）
- **建構階段** - package.json, bundle.json
- **啟動階段** - secret.ls, nginx, docker
- **執行階段** - mail 範本, key, 動態設定

#### 依版控分類
- **進版控** - base/ 下的範例設定
- **不進版控** - private/ 下的私密設定

## 主設定檔 (secret.ls)

位置: `config/private/secret.ls`

### 完整範例
```livescript
module.exports =
  # 前端站點目錄名稱
  base: 'base'  # 或 'web'

  # 網站 URL
  url: 'http://localhost:3000'

  # 伺服器 port
  port: 3000

  # Session 設定
  session:
    secret: 'your-random-secret-key'
    max-age: 365 * 86400 * 1000  # 1年

  # 資料庫設定
  db:
    io-pg:
      uri: 'postgresql://user:pass@localhost:5432/dbname'
      connection-timeout: 2000

  # Redis 設定
  redis:
    enabled: true
    host: 'localhost'
    port: 6379
    # password: 'redis-password'

  # 郵件設定
  mail:
    provider: 'mailgun'  # 或 'smtp'
    config:
      # Mailgun
      auth:
        api_key: 'key-xxx'
        domain: 'mg.example.com'
      # SMTP
      # host: 'smtp.example.com'
      # port: 587
      # secure: false
      # auth:
      #   user: 'user'
      #   pass: 'pass'
    from: 'noreply@example.com'

  # Log 設定
  log:
    level: 'debug'  # 或 'info'（生產建議）

  # CSRF 設定
  csrf:
    enabled: true

  # 上傳設定
  upload:
    max-size: 10 * 1024 * 1024  # 10MB
    allowed-types: <[image/jpeg image/png application/pdf]>

  # OAuth 設定
  oauth:
    facebook:
      client-id: 'xxx'
      client-secret: 'xxx'
      callback-url: 'http://localhost:3000/auth/facebook/callback'
    google:
      client-id: 'xxx'
      client-secret: 'xxx'
      callback-url: 'http://localhost:3000/auth/google/callback'
    line:
      channel-id: 'xxx'
      channel-secret: 'xxx'
      callback-url: 'http://localhost:3000/auth/line/callback'

  # 自訂設定
  custom:
    feature-flag: true
    api-keys: {...}
```

### 載入設定
```livescript
# 預設載入 secret.ls
./start

# 載入特定設定檔
./start -c demo       # config/private/demo.ls
./start -c staging    # config/private/staging.ls
```

## 資料庫設定 (config/base/db/)

### schema.sql
資料庫結構定義。

```sql
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  email VARCHAR(255) UNIQUE NOT NULL,
  password VARCHAR(255) NOT NULL,
  name VARCHAR(255),
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users(email);
```

### 初始化
```bash
psql -U user -d dbname -f config/base/db/schema.sql
```

## 郵件範本 (config/base/mail/)

### 目錄結構
```
config/base/mail/
└─ intl/
   ├─ en/
   │  ├─ reset-password.txt
   │  └─ welcome.html
   └─ zh-TW/
      ├─ reset-password.txt
      └─ welcome.html
```

### 範本格式
使用 template-text 語法。

```
# reset-password.txt
Hi {{name}},

Click the link below to reset your password:
{{url}}/reset?token={{token}}

This link will expire in 24 hours.
```

### 使用
```livescript
backend.mail-queue.send do
  template: 'reset-password'
  locale: 'zh-TW'
  data:
    name: 'John'
    email: 'john@example.com'
    token: 'abc123'
```

## Nginx 設定 (config/base/nginx/)

### default
基本站點設定。

```nginx
server {
  listen 80;
  server_name example.com;

  root /path/to/frontend/base/static;
  index index.html;

  # 靜態檔案
  location /assets/ {
    expires 1y;
    add_header Cache-Control "public, immutable";
  }

  # API 代理
  location /api/ {
    proxy_pass http://localhost:3000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
  }

  # SPA fallback
  location / {
    try_files $uri $uri/ /index.html;
  }
}
```

### ssl
SSL 設定範本。

```nginx
server {
  listen 443 ssl http2;
  server_name example.com;

  ssl_certificate /path/to/cert.pem;
  ssl_certificate_key /path/to/key.pem;

  # ... 其他設定
}
```

## Docker 設定 (config/base/docker/)

### compose.yaml
```yaml
version: '3.8'

services:
  db:
    image: postgres:14
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: password
      POSTGRES_DB: dbname
    ports:
      - "5432:5432"
    volumes:
      - db-data:/var/lib/postgresql/data

  redis:
    image: redis:7
    ports:
      - "6379:6379"

  app:
    build: .
    ports:
      - "3000:3000"
    depends_on:
      - db
      - redis
    environment:
      NODE_ENV: production

volumes:
  db-data:
```

### Dockerfile
```dockerfile
FROM node:18

WORKDIR /app

COPY package*.json ./
RUN npm ci --production

COPY . .
RUN npm run prebuild

CMD ["npm", "start"]
```

## 設定管理模組 (@servebase/config)

### 讀取設定
```livescript
config = require '@servebase/config'

# 讀取設定檔
cfg = config.from "private/secret"

# 讀取郵件範本
template = config.from "mail/intl/zh-TW/reset-password.txt"
```

### 動態設定
可在執行階段根據不同條件載入設定。

```livescript
# 根據網域載入設定
domain = req.hostname
cfg = config.from "private/#{domain}"
```

## 金鑰管理 (config/private/key/)

### 用途
- JWT 簽章
- 加密敏感資料
- OAuth secret

### 生成金鑰
```bash
# 生成 RSA 金鑰對
openssl genrsa -out config/private/key/private.pem 2048
openssl rsa -in config/private/key/private.pem -pubout -out config/private/key/public.pem
```

### 使用
```livescript
fs = require 'fs'
jwt = require 'jsonwebtoken'

private-key = fs.read-file-sync 'config/private/key/private.pem'
public-key = fs.read-file-sync 'config/private/key/public.pem'

# 簽章
token = jwt.sign {user-id: 123}, private-key, {algorithm: 'RS256'}

# 驗證
payload = jwt.verify token, public-key, {algorithms: ['RS256']}
```

## 多環境設定

### 開發環境
```livescript
# config/private/dev.ls
module.exports =
  base: 'base'
  url: 'http://localhost:3000'
  db:
    io-pg:
      uri: 'postgresql://localhost/myapp_dev'
  log:
    level: 'debug'
```

### 測試環境
```livescript
# config/private/test.ls
module.exports =
  base: 'base'
  url: 'http://test.example.com'
  db:
    io-pg:
      uri: 'postgresql://localhost/myapp_test'
  log:
    level: 'info'
```

### 生產環境
```livescript
# config/private/prod.ls
module.exports =
  base: 'web'
  url: 'https://example.com'
  db:
    io-pg:
      uri: process.env.DATABASE_URL  # 從環境變數讀取
  redis:
    host: process.env.REDIS_HOST
  log:
    level: 'info'
  mail:
    provider: 'mailgun'
    config:
      auth:
        api_key: process.env.MAILGUN_API_KEY
        domain: process.env.MAILGUN_DOMAIN
```

### 切換環境
```bash
./start -c dev      # 開發
./start -c test     # 測試
./start -c prod     # 生產
```

## 設定最佳實踐

### 安全性
- 不要將 `config/private/` 加入版控
- 使用環境變數儲存敏感資訊
- 定期輪換金鑰和密碼

### 組織
- 公開範例放 `config/base/`
- 每個環境一個設定檔
- 使用有意義的設定檔名稱

### 文件
- 在 `config/base/` 提供完整範例
- 註解說明每個設定項目
- 建立 README 說明設定流程

### 版本管理
- `config/base/` 進版控
- `config/private/secret.ls` 不進版控
- 提供 `secret.ls.example` 作為範本

### 預設值
在程式中提供合理的預設值：
```livescript
port = config.port or 3000
log-level = config.{}log.level or 'info'
```
