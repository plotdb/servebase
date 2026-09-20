-- mailspool: 有紀錄與重試的寄信佇列.
--
-- 與 backend/engine/mail-queue.ls 的分工: mail-queue 是 transport
-- ( nodemailer 封裝 / sanitize / blacklist / 樣板渲染 ), 這裡是持久化的
-- 派送層. mail-queue 原本的記憶體 @list 會被這裡取代 - 那個佇列 process
-- 重啟就整批消失, 而且失敗時照樣 resolve, 呼叫端拿不到任何可追蹤的資料.
--
-- 一封信一列 ( mailspool_item ), 不是一批一列: 逐封追蹤 / 逐封重試 /
-- 斷點續傳都需要能用 SQL 直接問「哪些還沒寄」.

create table if not exists mailspool (
  key serial primary key,
  owner int references users(key),

  -- 應用層自行決定的分群鍵, 不加 FK - servebase 沒有 brd / org 這些概念.
  -- grantdash 放 brd slug.
  scope text,

  name text,

  -- 內容來源, 兩種形式:
  --   {subject, content, columns}  inline: subject 用 {{欄位}} 代換,
  --                                content 是 html, 用 <span data-var> chip 代換
  --   {template: "reset-password"} 樣板: 走 mail-queue 的 get-content,
  --                                讀 config/*/mail/<name>.yaml 後 #{key} 代換
  -- 另有 sender / replyto / lng.
  -- resumable = false 時這裡只會有 subject / sender / replyto - content 與
  -- columns 不寫進來, 那正是「內容不落地」的意思.
  detail jsonb,

  -- draft: 編輯中 ( 只有 inline 形式會經過這個狀態 )
  -- scheduled: 已排程, 等 scheduledtime 到
  -- sending: worker 處理中
  -- done: 所有 item 都到終態 ( sent / failed / skipped )
  -- canceled: 使用者取消, 未寄的一併停掉
  -- aborted: 不可續傳的批次寄到一半就斷了 ( 見 resumable ). 與 canceled
  --          的差別在於這不是使用者的決定, 而且剩下的沒寄出去
  -- paused: 使用者按了暫停. worker 只認 scheduled / sending, 所以改成這個
  --         狀態就停下來了. 回復時看 starttime 決定要回到哪一個.
  --         只有可續傳的批次能暫停 - 不落地的那種是前端在推, 停不了.
  status text not null default 'draft'
    constraint mailspool_status check (
      status in ('draft','scheduled','sending','paused','done','canceled','aborted')
    ),

  -- 內容是否留在 DB 裡可供 worker 續傳.
  -- false = 內容從頭到尾沒寫進來 ( record = 'none' ), 由前端逐批即時寄出.
  -- 這種批次斷了就補不回來 - worker 不會、也無法接手, 只能標成 aborted.
  resumable bool not null default true,

  -- 預期要寄幾封. 只有 resumable = false 需要: 沒有 item 可以當進度表,
  -- 得靠這個數字才知道中斷時到底寄完了沒.
  expected int,

  -- 內容保留政策. 決定「存什麼」, 與 expiretime 的「存多久」正交.
  --   full     樣板與變數都留, 事後可重現整封信的內容
  --   metadata 寄完就清掉 detail 的內容與 item 的 vars, 只留收件者 / 狀態 /
  --            時間 / 錯誤. 給密碼重設這類信用 - 它們的內容含可用的 token,
  --            明文躺在 DB 裡本身就是風險, 而且 failed 的紀錄會一直留著
  --   none     不落地, 只即時寄送
  record text not null default 'full'
    constraint mailspool_record check (record in ('full','metadata','none')),

  -- 紀錄保留到何時, 由 worker 清掉. null = 沿用系統預設天數.
  -- email 本身是個資, 留著不清不只是空間問題.
  expiretime timestamptz,

  -- null = 立刻開始 ( 送出當下 )
  scheduledtime timestamptz,
  starttime timestamptz,
  donetime timestamptz,

  createdtime timestamptz not null default now(),
  deleted bool default false
);

create index if not exists mailspool_scope_index on mailspool (scope);

-- worker 撈待處理批次用
create index if not exists mailspool_pending_index
  on mailspool (status, scheduledtime)
  where status in ('scheduled','sending');

-- worker 清過期紀錄用
create index if not exists mailspool_expire_index on mailspool (expiretime)
  where expiretime is not null;

create table if not exists mailspool_item (
  key serial primary key,
  batch int references mailspool(key) on delete cascade not null,

  -- 原始清單中的列序, 供預覽翻頁與列表排序對齊
  idx int not null default 0,

  email text not null,

  -- 該列的變數 {欄位名: 值}. 不用 `row` 當欄位名 - 那是 SQL 保留字.
  -- record = 'metadata' 時, 寄完會被清成 null.
  vars jsonb,

  -- pending: 等著寄
  -- sending: worker 取走了, 尚未回報 ( 卡住的會被回收成 pending )
  -- sent: sendMail 成功. 注意這只代表送進 SMTP/mailgun, 不等於送達 -
  --       真正的送達要靠 provider webhook 回寫 ( 見 msgid )
  -- failed: 重試用盡仍失敗
  -- skipped: email 無效或在黑名單, 不寄
  status text not null default 'pending'
    constraint mailspool_item_status check (
      status in ('pending','sending','sent','failed','skipped')
    ),

  retry int not null default 0,
  error text,

  -- provider 的 message-id, 供之後接 webhook 回寫 delivered/bounced
  msgid text,

  sendtime timestamptz,
  updatedtime timestamptz not null default now()
);

create index if not exists mailspool_item_batch_index
  on mailspool_item (batch, idx);

-- worker 撈待寄 item 用
create index if not exists mailspool_item_pending_index
  on mailspool_item (batch, status) where status in ('pending','sending');
