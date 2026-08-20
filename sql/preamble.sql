-- Run by `sqlcmd` immediately before every query this config executes, via the
-- `SQLCMDINI` environment variable set in `lua/plugin/database.lua`.
--
-- Two constraints, both worth respecting:
--
--   1. This runs before EVERY `sqlcmd` invocation -- not only the queries you type, but
--      also the schema introspection `vim-dadbod-ui` uses to fill the drawer and that
--      `vim-dadbod-completion` uses to complete table and column names.
--
--   2. It must therefore produce NO OUTPUT. Anything printed here is prepended to the
--      result buffer, and worse, is parsed as part of the table list during
--      introspection -- so a stray `PRINT` corrupts completion rather than just looking
--      untidy. `SET` statements are silent; `PRINT` and `SELECT` are not.
--
-- Uncomment what you want.

-- Suppresses the "(N rows affected)" line after every statement. The usual first choice,
-- and the one that most reduces noise in the result buffer.
-- SET NOCOUNT ON;

EXEC sp_set_session_context N'organisationIdFk', '-666';
EXEC sp_set_session_context N'organisationId', '11111111-2222-3333-4444-555555555555';
EXEC sp_set_session_context N'userId', '11111111-2222-3333-4444-555555555555';

-- Against a production database these make an exploratory query unable to block on
-- someone else's transaction, and unable to make anyone else wait on yours. The cost is
-- real and worth stating: dirty reads -- rows you may see that are later rolled back.
-- SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
-- SET LOCK_TIMEOUT 5000;
