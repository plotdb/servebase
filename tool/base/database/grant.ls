require! <[@servebase/tool/init]>

init!
  .then ({backend}) ->

    cfg = backend.config.db.postgresql

    dbname = cfg.database
    username = cfg.user
    sql-cmd = """
    -- 切到該資料庫
    \c #{dbname}

    -- 對所有已存在的 tables
    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO #{username};

    -- 對所有已存在的 sequences
    GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO #{username};

    -- 對所有已存在的 functions
    GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO #{username};

    -- 讓之後新建的 tables/sequences/functions 自動給權限
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO #{username};
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO #{username};
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON FUNCTIONS TO #{username};
    """
    console.log sql-cmd

  .then -> process.exit!
