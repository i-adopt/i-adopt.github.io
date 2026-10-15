
-- bibentry.lua — render [@key]{.bibentry} as a full CSL-formatted entry inline
-- Preserves original citation for References using format-specific hiding
-- Usage: [@key]{.bibentry} will render the full bibliography entry inline
--        while maintaining the References section

PANDOC_VERSION:must_be_at_least {2,19,1}

local utils = require 'pandoc.utils'
local citeproc = utils.citeproc

local function render_full_entry_from_inlines(inlines, doc_meta)
  local para = pandoc.Para(inlines)
  local mini_doc = pandoc.Pandoc({para}, doc_meta)
  local processed_doc = citeproc(mini_doc)

  local bibliography_content = nil

  local function find_csl_entry(block)
    if block.t == "Div" and block.classes and block.classes:includes("csl-entry") then
      if block.content and #block.content > 0 then
        for _, content in ipairs(block.content) do
          if content.t == "Para" then
            bibliography_content = content.content
            return
          elseif content.t == "Plain" then
            bibliography_content = content.content
            return
          end
        end
        bibliography_content = block.content
      end
    end
  end

  pandoc.walk_block(pandoc.Div(processed_doc.blocks), {
    Div = find_csl_entry
  })

  return bibliography_content
end

-- Process after citeproc has run
function Pandoc(doc)
  local format = FORMAT or "html"

  local function process_para(para)
    local bibentry_found = false
    local bibentry_span = nil

    -- Look for bibentry spans in this paragraph
    for i, el in ipairs(para.content) do
      if el.t == "Span" and el.classes and el.classes:includes("bibentry") then
        bibentry_found = true
        bibentry_span = el
        break
      end
    end

    if not bibentry_found then
      return para
    end

    -- Render the full bibliography entry
    local entry_inlines = render_full_entry_from_inlines(bibentry_span.content, doc.meta)

    if entry_inlines then
      -- Create the full bibliography entry
      local full_entry = pandoc.Para(entry_inlines)

      -- Create hidden original citation using format-appropriate method
      local hidden_citation = nil

      if format:match("typst") then
        -- For Typst, create a properly hidden citation that preserves content for References
        local hide_start = pandoc.RawInline("typst", "#hide[")
        local hide_end = pandoc.RawInline("typst", "]")
        -- Wrap the citation content in hide
        local wrapped_content = {hide_start}
        for _, item in ipairs(para.content) do
          table.insert(wrapped_content, item)
        end
        table.insert(wrapped_content, hide_end)
        hidden_citation = pandoc.Para(wrapped_content)
      else
        -- For HTML and other formats, use CSS
        local hidden_para = pandoc.Para(para.content)
        hidden_citation = pandoc.Div({hidden_para},
          pandoc.Attr("", {}, {
            style="position:absolute;left:-10000px;top:-10000px;width:1px;height:1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;"
          }))
      end

      -- Return both elements
      if hidden_citation then
        return pandoc.Div({full_entry, hidden_citation})
      else
        return full_entry
      end
    else
      -- Fallback: remove bibentry class
      local new_content = {}
      for _, el in ipairs(para.content) do
        if el.t == "Span" and el.classes and el.classes:includes("bibentry") then
          local new_classes = pandoc.List()
          for _, class in ipairs(el.classes) do
            if class ~= "bibentry" then
              new_classes:insert(class)
            end
          end
          el.classes = new_classes
        end
        new_content[#new_content + 1] = el
      end
      return pandoc.Para(new_content)
    end
  end

  -- Process all blocks
  local new_blocks = {}
  for _, block in ipairs(doc.blocks) do
    if block.t == "Para" then
      new_blocks[#new_blocks + 1] = process_para(block)
    else
      new_blocks[#new_blocks + 1] = block
    end
  end

  return pandoc.Pandoc(new_blocks, doc.meta)
end
