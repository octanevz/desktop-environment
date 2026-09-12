-- Run headlessly by setup-04-lazyvim.sh, after "Lazy! sync" has installed the
-- plugins:
--
--   nvim --headless -c "luafile config/nvim/install-tools.lua"
--
-- The plugin sync leaves three things for the first interactive start: the
-- treesitter parsers, the Mason tools (formatters, linters) and the language
-- servers. nvim-treesitter and mason.nvim only fetch them once they load, and
-- a headless sync never loads them. This script loads them, so LazyVim's
-- config for each runs and starts the same installs it would start on that
-- first start - except the language servers: mason-lspconfig deliberately
-- skips its ensure_installed when headless, so those are started here, from
-- the list it was given. Then everything is waited for.
--
-- Exits 1 when an install fails or the wait times out, listing what is
-- missing; the caller reports it and leaves the rest to ":Lazy sync",
-- ":Mason" and ":TSUpdate" inside Neovim.

local TIMEOUT = 15 * 60 * 1000

local function contains(list, item)
  return vim.tbl_contains(list, item)
end

-- mason.nvim first, on its own: LazyVim's config for it refreshes the
-- registry (asynchronously) and nvim-lspconfig's config needs the registry to
-- know which servers Mason can install - on a machine without a registry
-- cache yet it would otherwise find none. Waiting for that refresh is also
-- what makes it safe to look packages up below, without starting a second
-- refresh alongside.
require("lazy").load({ plugins = { "mason.nvim" } })

local mr = require("mason-registry")
local failed = {}
mr:on("package:install:failed", function(pkg)
  failed[#failed + 1] = pkg.name
end)

if not vim.wait(TIMEOUT, function()
  return mr.has_package("stylua")
end, 500) then
  io.stderr:write("The Mason registry did not become available.\n")
  vim.cmd("cquit 1")
end

require("lazy").load({ plugins = { "nvim-lspconfig", "nvim-treesitter" } })

-- The tools LazyVim installs itself (mason.nvim's ensure_installed, extended by
-- the extras) and the servers it leaves out when headless (mason-lspconfig's
-- ensure_installed, built by LazyVim from the configured servers), the latter
-- translated from lspconfig names to Mason package names.
local tools = LazyVim.opts("mason.nvim").ensure_installed or {}
local servers = {}
local to_package = require("mason-lspconfig").get_mappings().lspconfig_to_package
for _, server in ipairs(require("mason-lspconfig.settings").current.ensure_installed or {}) do
  local name = to_package[server] or server
  if not contains(tools, name) and not contains(servers, name) then
    servers[#servers + 1] = name
  end
end

for _, name in ipairs(servers) do
  local pkg = mr.get_package(name)
  if not pkg:is_installed() and not pkg:is_installing() then
    pkg:install()
  end
end

local parsers = LazyVim.opts("nvim-treesitter").ensure_installed or {}

-- A package directory appears as soon as an install starts (the npm ones
-- are built in place), so "installed" is the directory without an install
-- still running.
local function installed(name)
  local pkg = mr.get_package(name)
  return pkg:is_installed() and not pkg:is_installing()
end

local function missing()
  local list = {}
  for _, name in ipairs(vim.list_extend(vim.deepcopy(tools), servers)) do
    if not installed(name) then
      list[#list + 1] = name
    end
  end
  local have = require("nvim-treesitter").get_installed("parsers")
  for _, lang in ipairs(parsers) do
    if not contains(have, lang) then
      list[#list + 1] = "treesitter parser " .. lang
    end
  end
  return list
end

-- Keep waiting after a failure until the other installs have finished too,
-- so that one failed package does not leave the rest half-done.
local function installing()
  for _, name in ipairs(vim.list_extend(vim.deepcopy(tools), servers)) do
    if mr.get_package(name):is_installing() then
      return true
    end
  end
  return false
end

vim.wait(TIMEOUT, function()
  return #missing() == 0 or (#failed > 0 and not installing())
end, 1000)

local left = missing()
if #left > 0 then
  io.stderr:write("Not installed: " .. table.concat(left, ", ") .. "\n")
  vim.cmd("cquit 1")
end
io.stdout:write(
  string.format(
    "Installed %d tools, %d language servers and %d treesitter parsers.\n",
    #tools,
    #servers,
    #parsers
  )
)
vim.cmd("quitall")
