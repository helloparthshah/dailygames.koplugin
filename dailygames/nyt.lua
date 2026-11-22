--[[
NYT puzzle fetchers. Each returns a normalized table, or nil + error message.
]]

local Http = require("dailygames/http")

local NYT = {}

local BASE = "https://www.nytimes.com/svc"

function NYT.wordle(date)
    local data, err = Http.getJson(BASE .. "/wordle/v2/" .. date .. ".json")
    if not data then return nil, err end
    if type(data.solution) ~= "string" or #data.solution ~= 5 then
        return nil, "unexpected Wordle data"
    end
    return {
        solution = data.solution:upper(),
        number = data.days_since_launch,
    }
end

function NYT.connections(date)
    local data, err = Http.getJson(BASE .. "/connections/v2/" .. date .. ".json")
    if not data then return nil, err end
    if type(data.categories) ~= "table" then
        return nil, "unexpected Connections data"
    end

    local categories, board = {}, {}
    for level, cat in ipairs(data.categories) do
        local words = {}
        for _, card in ipairs(cat.cards or {}) do
            local word = card.content or card.image_alt_text or "?"
            table.insert(words, word)
            -- Lay the board out the way NYT does (card.position is 0-based).
            table.insert(board, { word = word, pos = card.position or #board })
        end
        table.insert(categories, { title = cat.title or "?", words = words, level = level })
    end
    table.sort(board, function(a, b) return a.pos < b.pos end)
    local ordered = {}
    for i, card in ipairs(board) do
        ordered[i] = card.word
    end
    return { categories = categories, board = ordered, number = data.id }
end

function NYT.strands(date)
    local data, err = Http.getJson(BASE .. "/strands/v2/" .. date .. ".json")
    if not data then return nil, err end
    if type(data.startingBoard) ~= "table" then
        return nil, "unexpected Strands data"
    end

    local board = {}
    for r, row in ipairs(data.startingBoard) do
        board[r] = row:upper()
    end
    -- Coordinates are { {row, col}, ... } (0-based). Anything else is ignored and
    -- words are then accepted by spelling alone.
    local function validCoords(list)
        if type(list) ~= "table" or #list == 0 then return nil end
        for _, rc in ipairs(list) do
            if type(rc) ~= "table" or type(rc[1]) ~= "number" or type(rc[2]) ~= "number" then
                return nil
            end
        end
        return list
    end

    local theme_words, coords = {}, {}
    for _, w in ipairs(data.themeWords or {}) do
        table.insert(theme_words, w:upper())
    end
    for w, list in pairs(data.themeCoords or {}) do
        coords[w:upper()] = validCoords(list)
    end
    local spangram = (data.spangram or ""):upper()
    coords[spangram] = validCoords(data.spangramCoords)
    return {
        clue = data.clue or "Find the theme words",
        board = board,
        theme_words = theme_words,
        spangram = spangram,
        coords = coords, -- word -> { {row, col}, ... } (0-based)
    }
end

--- kind: "mini" or "daily". The daily puzzle needs an NYT subscription cookie (NYT-S).
function NYT.crossword(kind, nyt_s_cookie)
    local headers
    if nyt_s_cookie and nyt_s_cookie ~= "" then
        headers = { ["Cookie"] = "NYT-S=" .. nyt_s_cookie }
    end
    local data, err = Http.getJson(BASE .. "/crosswords/v6/puzzle/" .. kind .. ".json", headers)
    if not data then return nil, err end
    local body = type(data.body) == "table" and data.body[1]
    if not body or not body.cells or not body.dimensions then
        return nil, "unexpected crossword data"
    end

    -- Cells: 1-based, blocks have no answer. Clue references are converted to 1-based.
    local cells = {}
    for i, c in ipairs(body.cells) do
        local cell = { answer = c.answer and c.answer:upper() or nil, label = c.label, clues = {} }
        for _, ci in ipairs(c.clues or {}) do
            table.insert(cell.clues, ci + 1)
        end
        cells[i] = cell
    end

    local clues = {}
    for _, cl in ipairs(body.clues or {}) do
        local text = ""
        if type(cl.text) == "table" and cl.text[1] then
            text = cl.text[1].plain or cl.text[1].formatted or ""
        end
        local cl_cells = {}
        for _, ci in ipairs(cl.cells or {}) do
            table.insert(cl_cells, ci + 1)
        end
        table.insert(clues, {
            label = tostring(cl.label or "?"),
            dir = cl.direction or "Across",
            text = text,
            cells = cl_cells,
        })
    end

    return {
        width = body.dimensions.width,
        height = body.dimensions.height,
        cells = cells,
        clues = clues,
        date = data.publicationDate or os.date("%Y-%m-%d"),
    }
end

return NYT
