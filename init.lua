-- Load order is significant: `config.vim` sets the leader keys, and they must exist
-- before `config.lazy` loads plugin specs, since specs declare `<leader>` mappings at
-- spec time. Keep this list to requires only -- no logic belongs here.
require("config.vim")
require("config.lazy")
require("config.keymap")
require("config.autocommand")
require("config.filetype")
