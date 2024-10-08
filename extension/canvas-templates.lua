--[[
MIT LICENSE
Copyright © 2024 John Riggles

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]]

-- TODO: convert to extension

-- stop complaining about unknow Aseprite API methods
---@diagnostic disable: undefined-global
-- ignore dialogs which are defined with local names for readablity, but may be unused
---@diagnostic disable: unused-local

local preferences = {}
local templatesFilePath = app.fs.userConfigPath .. "extensions/canvas-templates/templates.json"

-- load canvas size templates from templates.json file
local function loadTemplates()
  local file = assert(io.open(templatesFilePath, "r+"), "Could not load templates file")
  local data = file:read("*a")
  local templates = json.decode(data)
  file:close()
  return templates
end

local function fileExists(path)
  local f = io.open(path, "r")
  return f ~= nil and io.close(f)
end

local function openTemplatesJSON()
  -- use os.execute to open the templates.json file in the default external editor
  if not fileExists(templatesFilePath) then
    app.alert{
      title = "Template File Not Found",
      text = "The file \"" .. templatesFilePath .. "\" does not exist."
    }
  end
  if app.os.macos then
    os.execute("open \"" .. templatesFilePath .. '"')
  elseif app.os.windows then
    os.execute("start \"" .. '"' .. templatesFilePath .. '"')
  end
end

local function toggleCategory(dlg, toggleId, templates)
  -- get the value of the toggle (checkbox) that triggered this callback
  local visibility = dlg.data[toggleId]
  -- hide the separator so there aren't a bunch left on the dlg when categories are hidden
  dlg:modify { id = toggleId .. "Separator", visible = visibility }
  -- iterate over the templates data to show/hide all items in the appropriate category
  for category, templateNames in pairs(templates) do
    for templateName, _size in pairs(templateNames) do
      if toggleId == category then
        dlg:modify { id = templateName, visible = visibility }
        if visibility then
          dlg:modify { id = toggleId, label = "▼"}
        else
          dlg:modify { id = toggleId, label = "►"}
        end
      end
    end
  end
end

local function badJSONDlg()
  local loadErrorDlg = Dialog("Error Reading Template File")
  :label { text = "There is a problem with your templates.json file." }
  :newrow()
  :label { text = "Please ensure the contents of this file are properly formatted!" }
  :newrow()
  :label { text = "Attempted to read from:" }
  :newrow()
  :label { text = templatesFilePath }
  :button { text = "OK", hexpand = false }
  :button { text = 'Open "templates.json"...', onclick = openTemplatesJSON }
  :show()
end

local function sortResolutions(category)
  local resolutions = {}
  for name, dimensions in pairs(category) do
    table.insert(
      resolutions,
      { name = name, width = dimensions.width, height = dimensions.height }
    )
  end

  table.sort(
    resolutions,
    function(a, b)
      return a.width < b.width
    end
  )
  return resolutions
end

local function templateSelectionDialog(templates)
  local dlg = Dialog("Canvas Size Templates")
  -- show dimensions of currently selected template
  dlg:label { id = "sizeHint", text = "Template Size: (choose a template)" }
  dlg:check {
    id = "rotate",
    text = "Rotate 90 degrees?",
    selected = false,
    hexpand = false,
    onclick = function()  -- update sizeHint label (swap WxH values) when toggled
      dlg:modify {
        id = "sizeHint",
        text = dlg.data["sizeHint"]:gsub("(%d+)x(%d+)", "%2x%1")
      }
    end
  }

  -- get template categories
  for category, templateNames in pairs(templates) do
    -- add labeled separator for each category
    dlg:separator()
    dlg:check {
      align = Align.CENTER,
      id = category,
      text = category,
      label = "▼",
      selected = true, -- checked, categories should be visible by default
      hexpand = true,
      onclick = function() toggleCategory(dlg, category, templates) end,
    }
    -- this separator has an id so it can be hidden by toggleCategory as-needed
    dlg:separator { id = category .. "Separator" }
    local i = 1  -- items-per-row counter
    -- get sizes in each category
    templateNames = sortResolutions(templateNames)
    for templateName, data in pairs(templateNames) do
      -- get width and height without decimals
      local wStatus, wInt = pcall(math.floor, data.width)
      local hStatus, hInt = pcall(math.floor, data.height)

      if not wStatus and not hStatus then
        badJSONDlg()
        return
      end
      -- add radio button for each size
      dlg:radio {
        -- hexpand = false,
        id = data.name,
        text = data.name,
        onclick = function ()
          if dlg.data["rotate"] then  -- rotation enabled, swap width and height values
            wInt, hInt = hInt, wInt
          end
          dlg:modify {
            id = "sizeHint",
            text = "Template Size: " .. wInt .. "x" .. hInt
          }
        end
      }
      -- insert a newrow after every 2 items
      local itemsPerRow = 2
      if i % itemsPerRow == 0 then
        dlg:newrow()
      end
      i = i + 1
    end
  end

  dlg:separator { text = "Edit Templates" }
  dlg:button {
    id = "openJson",
    text = 'Open "templates.json"...',
    onclick = function()
      openTemplatesJSON()
      dlg:close()
    end
  }
  dlg:label { text = "(opens in default external editor)", align = Align.CENTER }

  dlg:separator()
  dlg:button {
    id = "select",
    text = "Select",
    onclick = function() -- apply selected template
      for category, templateNames in pairs(templates) do
        for templateName, size in pairs(templateNames) do
          if dlg.data[templateName] then
            -- create a new sprite with the given dimensions
            local w, h
            if not dlg.data["rotate"] then
              w = size.width
              h = size.height
            else  -- swap the width and height values
              w = size.height
              h = size.width
            end
            app.command.NewFile{ ui = false, width = w, height = h }
          end
        end
      end
      dlg:close()
    end
  }
  dlg:button { id = "cancel", text = "Cancel" }
  dlg:show()
end

local function main()
  if app.apiVersion < 28 then
    return app.alert("This extension requires Aseprite version 1.3.7 or later")
  end

  local status, templateData = pcall(loadTemplates)
  if not status then
    badJSONDlg()
  end
  templateSelectionDialog(templateData)
  app.command.refresh()
end

-- Aseprite plugin API stuff...
---@diagnostic disable-next-line: lowercase-global
function init(plugin) -- initialize extension
  preferences = plugin.preferences

  plugin:newCommand {
    id = "openTemplates",
    title = "Canvas Templates...",
    group = "file_recent",
    onclick = main -- run main function
  }
end

---@diagnostic disable-next-line: lowercase-global
function exit(plugin)
  -- no cleanup
  return nil
end
