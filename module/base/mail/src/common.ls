# 群發信的樣板代換工具.
#
# 前後端共用: 前端預覽與後端寄送要走同一份邏輯, 否則會出現
# 「預覽看到一種、收到信是另一種」.

common =
  # 欄位名: 允許中文與空白 ( 標題列直接當欄位名 ), 但不能有 `{}` 與引號,
  # 否則會破壞 {{}} 語法與 html attribute.
  is-valid-column: (n) ->
    n = "#{n or ''}".trim!
    return !!(n and n.length <= 64 and !/[{}"'<>]/.exec(n))

  escape-html: (v) ->
    "#{if v? => v else ''}"
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')

  # `{{欄位名}}` 代換, 給純文字欄位 ( subject ) 用.
  # 找不到的欄位代成空字串 - 寄出前的 lint 會先提醒, 這裡不該擋下整批.
  render-text: (tpl, vars = {}) ->
    "#{tpl or ''}".replace /\{\{([^{}]*)\}\}/g, (m, name) ->
      name = "#{name}".trim!
      return if vars[name]? => "#{vars[name]}" else ''

  # quill var chip 代換, 給 html 本文用.
  #
  # 用 regex 而非 DOM parse: 這支函式前後端共用, 後端沒有 document,
  # 不想為了代換把 jsdom 拉進這個模組.
  # chip 由 VarBlot 產生. attribute 順序由 quill 決定, 所以 pattern 對順序
  # 保持寬鬆.
  #
  # quill 2 的 embed 不是單純的 <span data-var="X">X</span>, 而會在裡面再包
  # 一層並前後夾零寬字元:
  #   <span class="mm-var" data-var="姓名">﻿<span contenteditable="false">姓名</span>﻿</span>
  # 所以內部要允許一層巢狀 span - 否則非貪婪的比對會停在內層的 </span>,
  # 把外層的結束標籤留在信件裡, 版面就破了.
  render-html: (tpl, vars = {}) ->
    self = @
    re = /<span[^>]*\sdata-var="([^"]*)"[^>]*>(?:<span[^>]*>[\s\S]*?<\/span>|[^<])*<\/span>/g
    html = "#{tpl or ''}".replace re, (m, name) ->
      name = "#{name}".trim!
      return self.escape-html(if vars[name]? => vars[name] else '')
    return self.tighten html

  # quill 把每一行都包成一個 <p>, 而它自己的 css 把 p 的 margin 歸零 - 在
  # 編輯器裡「一行就是一行, 空行才是空行」. email client 沒有那份 css, 預設
  # 會給 p 上下各約 1em, 同一份內容寄出去行距就散開了, 而且跟作者打字時看到
  # 的不一樣.
  #
  # 所以代換完順手把 margin 寫死在 style 上 - email 只認 inline style.
  # 預覽走的是同一支 render, 於是編輯器 / 預覽 / 實際收到的信三邊一致.
  # 已經自己帶 style 的 p 不動 ( 目前 toolbar 不會產生, 留著以防日後放寬 ).
  tighten: (html) ->
    "#{html or ''}".replace /<p(\s[^>]*)?>/g, (m, attr) ->
      attr = attr or ''
      if /\sstyle\s*=/.exec attr => return m
      return "<p#attr style=\"margin:0\">"

  # template 用到哪些欄位. 供寄出前 lint ( 有沒有用到不存在的欄位 ) 與
  # 「哪些 row 的這個欄位是空的」提示.
  used-vars: ({subject, content}) ->
    names = {}
    ("#{subject or ''}".match(/\{\{([^{}]*)\}\}/g) or [])
      .map (m) -> names[m.replace(/^\{\{|\}\}$/g, '').trim!] = true
    ("#{content or ''}".match(/<span[^>]*\sdata-var="([^"]*)"[^>]*>/g) or [])
      .map (m) ->
        r = /data-var="([^"]*)"/.exec(m)
        if r => names[r.1.trim!] = true
    return [k for k of names when k]

  # html 本文的純文字版, 給不吃 html 的 client.
  # 不求精準還原排版, 只求讀得懂: 區塊標籤換行, 其餘去標籤.
  to-text: (html) ->
    "#{html or ''}"
      # quill embed 夾的零寬字元 ( U+FEFF ), 留在純文字版裡會變成看不見的雜訊.
      # 要寫成跳脫形式 - 直接打那個字元, lexer 會把它當空白, `/` 就黏成 `//`
      .replace(/\uFEFF/g, '')
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<\/(p|div|h[1-6]|li|blockquote|tr)>/gi, '\n')
      .replace(/<li[^>]*>/gi, '- ')
      .replace(/<[^>]+>/g, '')
      .replace(/&nbsp;/g, ' ')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      # &amp; 要最後才還原, 否則 &amp;lt; 會被二次解碼
      .replace(/&amp;/g, '&')
      .replace(/\n{3,}/g, '\n\n')
      .trim!

  # 寄件者位址與顯示名稱組成一個 From. 預覽與實際寄送共用, 才不會出現
  # 「預覽看到一種、收到信是另一種」.
  #
  # sender 若本身就已經是 `名稱 <a@b>` 這種完整形式 ( 舊資料, 或使用者
  # 直接整串貼進來 ), 就原樣採用, 不再包一層.
  format-sender: ({sender, sendername} = {}) ->
    s = "#{(sender or '')}".trim!
    n = "#{(sendername or '')}".trim!
    if !s => return ''
    if ~s.indexOf('<') => return s
    if !n => return s
    # 顯示名稱裡的引號會破壞 From 的語法, 去掉
    return "\"#{n.replace(/[\"\\\\]/g, '')}\" <#s>"

  # 一列資料 -> 一封信的內容. 預覽與實際寄送都走這支, 兩邊才會一致.
  render: ({subject, content}, vars = {}) ->
    html = @render-html content, vars
    return {
      subject: @render-text(subject, vars)
      html: html
      text: @to-text(html)
    }

if mail? => for k,v of common => if typeof(v) == \object => mail{}[k] <<< v else mail[k] = v
