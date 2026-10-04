-- OrdenaBolsas: ordena las bolsas con /ordenar (API WoW 1.12 / Lua 5.0)
-- Comandos:
--   /ordenar            -> junta stacks incompletos y ordena las bolsas
--   /ordenar banco      -> ordena el banco (debe estar abierto)
--   /ordenar stop       -> cancela el proceso
--   /ordenar excluir N  -> excluye/incluye la bolsa N (0 = mochila, 1-4 = bolsas,
--                          -1 = banco, 5-10 = bolsas del banco)
--   /ordenar estado     -> muestra bolsas excluidas

local DELAY = 0.15      -- segundos entre pasos
local MAX_WAIT = 80     -- ticks esperando desbloqueo antes de abortar

-- Orden de categorias (nombre del tipo segun el idioma del cliente).
-- Si tu cliente esta en espanol, agrega aqui los nombres localizados.
local CATEGORY_ORDER = {
    ["Quest"] = 1, ["Misión"] = 1,
    ["Consumable"] = 2, ["Consumible"] = 2,
    ["Weapon"] = 3, ["Arma"] = 3,
    ["Armor"] = 4, ["Armadura"] = 4,
    ["Reagent"] = 5, ["Reactivo"] = 5,
    ["Trade Goods"] = 6,
    ["Recipe"] = 7, ["Receta"] = 7,
    ["Projectile"] = 8, ["Proyectil"] = 8,
    ["Container"] = 9, ["Quiver"] = 9, ["Contenedor"] = 9,
    ["Key"] = 10, ["Llave"] = 10,
    ["Miscellaneous"] = 11, ["Misceláneo"] = 11,
}

-- Objetos que siempre van al primer slot (itemID). 6948 = Piedra de hogar.
local PINNED_FIRST = {
    [6948] = true,
}

-- Bolsas especiales que se omiten automaticamente (nombres en ingles)
local SPECIAL_BAGS = {
    ["Soul Bag"] = true, ["Herb Bag"] = true, ["Enchanting Bag"] = true,
    ["Engineering Bag"] = true, ["Ammo Pouch"] = true, ["Quiver"] = true,
}

local queue = {}
local idx = 1
local lastOp = nil
local waited = 0
local timer = 0
local cursorTries = 0
local bankOpen = false
local sortingBank = false

local BAGS_LIST = { 0, 1, 2, 3, 4 }
local BANK_LIST = { -1, 5, 6, 7, 8, 9, 10 }

local frame = CreateFrame("Frame")
frame:Hide()

local function Msg(t)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99OrdenaBolsas:|r " .. t)
end

local function IsExcluded(bag)
    local db = OrdenaBolsas_DB
    if db and db.exclude and db.exclude[bag] then return true end
    if bag == 0 or bag == -1 then return false end
    local link = GetInventoryItemLink("player", ContainerIDToInventoryID(bag))
    if not link then return true end
    local s, e, id = string.find(link, "item:(%d+)")
    if not id then return false end
    local n, l, q, lv, itype, subtype = GetItemInfo("item:" .. id .. ":0:0:0")
    if itype == "Quiver" then return true end
    if subtype and SPECIAL_BAGS[subtype] then return true end
    return false
end

local function IsLocked(p)
    local tex, count, locked = GetContainerItemInfo(p[1], p[2])
    return locked
end

local function Stop(reason)
    frame:Hide()
    queue = {}
    idx = 1
    lastOp = nil
    waited = 0
    cursorTries = 0
    sortingBank = false
    if reason then Msg(reason) end
end

-- Lee todas las posiciones de las bolsas incluidas
local function Scan(bagList, pin)
    local positions, items, cur = {}, {}, {}
    local n = 0
    for bi = 1, table.getn(bagList) do
        local bag = bagList[bi]
        if not IsExcluded(bag) then
            for slot = 1, GetContainerNumSlots(bag) do
                n = n + 1
                positions[n] = { bag, slot }
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local tex, count, locked, q2 = GetContainerItemInfo(bag, slot)
                    local s, e, id = string.find(link, "item:(%d+)")
                    local name, l, quality, lv, itype, subtype, stack =
                        GetItemInfo("item:" .. id .. ":0:0:0")
                    if not name then
                        local s2, e2, nm = string.find(link, "%[(.-)%]")
                        name = nm
                    end
                    items[n] = {
                        id = tonumber(id),
                        name = name or "",
                        quality = quality or q2 or 0,
                        itype = itype or "",
                        subtype = subtype or "",
                        cat = CATEGORY_ORDER[itype or ""] or 50,
                        count = count or 1,
                        maxStack = stack,
                    }
                    local it = items[n]
                    if pin and PINNED_FIRST[it.id] then
                        it.rank = 0
                    elseif it.quality == 0 then
                        it.rank = 2
                    else
                        it.rank = 1
                    end
                    cur[n] = n
                end
            end
        end
    end
    return positions, items, cur, n
end

-- Paso 1: juntar stacks incompletos del mismo objeto
local function PlanMerges(positions, items, cur, n, ops)
    local groups = {}
    for pos = 1, n do
        local uid = cur[pos]
        if uid then
            local it = items[uid]
            if it.maxStack and it.maxStack > 1 and it.count < it.maxStack then
                if not groups[it.id] then groups[it.id] = {} end
                table.insert(groups[it.id], pos)
            end
        end
    end
    for id, list in pairs(groups) do
        table.sort(list, function(a, b)
            local ca, cb = items[cur[a]].count, items[cur[b]].count
            if ca ~= cb then return ca > cb end
            return a < b
        end)
        local d, s = 1, table.getn(list)
        while d < s do
            local dp, sp = list[d], list[s]
            local dit, sit = items[cur[dp]], items[cur[sp]]
            local space = dit.maxStack - dit.count
            if space <= 0 then
                d = d + 1
            else
                local moved = math.min(space, sit.count)
                dit.count = dit.count + moved
                sit.count = sit.count - moved
                table.insert(ops, { positions[sp], positions[dp], merge = true })
                if sit.count <= 0 then
                    cur[sp] = nil
                    s = s - 1
                end
            end
        end
    end
end

local function MakeCmp(items)
    return function(a, b)
        local x, y = items[a], items[b]
        if x.rank ~= y.rank then return x.rank < y.rank end
        if x.cat ~= y.cat then return x.cat < y.cat end
        if x.itype ~= y.itype then return x.itype < y.itype end
        if x.subtype ~= y.subtype then return x.subtype < y.subtype end
        if x.quality ~= y.quality then return x.quality > y.quality end
        if x.name ~= y.name then return x.name < y.name end
        if x.id ~= y.id then return x.id < y.id end
        if x.count ~= y.count then return x.count < y.count end -- parcial primero
        return a < b
    end
end

-- Paso 2: ordenar por intercambios.
-- Los objetos normales van desde el primer slot hacia delante.
-- Los grises (basura) se colocan desde el ULTIMO slot hacia atras.
local function PlanSort(positions, items, cur, n, ops)
    local uids = {}
    for pos = 1, n do
        if cur[pos] then table.insert(uids, cur[pos]) end
    end
    table.sort(uids, MakeCmp(items))

    -- posicion final de cada objeto
    local order = {}
    local front, back = 0, 0
    for k = 1, table.getn(uids) do
        local uid = uids[k]
        local target
        if items[uid].rank == 2 then
            target = n - back
            back = back + 1
        else
            front = front + 1
            target = front
        end
        table.insert(order, { uid, target })
    end

    for k = 1, table.getn(order) do
        local uid, pos = order[k][1], order[k][2]
        if cur[pos] ~= uid then
            local j = nil
            for q = 1, n do
                if cur[q] == uid then
                    j = q
                    break
                end
            end
            if j then
                -- primero se levanta el objeto (j, siempre ocupado) y se suelta en pos
                table.insert(ops, { positions[j], positions[pos] })
                local tmp = cur[pos]
                cur[pos] = cur[j]
                cur[j] = tmp
            end
        end
    end
end

local function Step()
    if lastOp then
        if CursorHasItem() then
            -- el objeto desplazado (o el resto de un stack) queda en el cursor:
            -- soltarlo en el slot de origen para completar el intercambio
            cursorTries = cursorTries + 1
            if cursorTries > 3 then
                Stop("no se pudo completar un movimiento, proceso cancelado.")
                return
            end
            PickupContainerItem(lastOp[1][1], lastOp[1][2])
            return
        end
        cursorTries = 0
        if IsLocked(lastOp[1]) or IsLocked(lastOp[2]) then
            waited = waited + 1
            if waited > MAX_WAIT then
                Stop("tiempo de espera agotado, proceso cancelado.")
            end
            return
        end
    elseif CursorHasItem() then
        Stop("hay un objeto en el cursor, proceso cancelado.")
        return
    end
    waited = 0
    local op = queue[idx]
    if not op then
        Stop("bolsas ordenadas.")
        return
    end
    idx = idx + 1
    PickupContainerItem(op[1][1], op[1][2])
    PickupContainerItem(op[2][1], op[2][2])
    lastOp = op
end

frame:SetScript("OnUpdate", function()
    timer = timer + arg1
    if timer < DELAY then return end
    timer = 0
    Step()
end)

local function Start(bank)
    if bank and not bankOpen then
        Msg("abre el banco primero.")
        return
    end
    if frame:IsVisible() then
        Msg("ya hay un proceso en curso (/ordenar stop para cancelar).")
        return
    end
    if CursorHasItem() then
        Msg("suelta el objeto que tienes en el cursor primero.")
        return
    end
    local positions, items, cur, n = Scan(bank and BANK_LIST or BAGS_LIST, not bank)
    local ops = {}
    PlanMerges(positions, items, cur, n, ops)
    PlanSort(positions, items, cur, n, ops)
    if table.getn(ops) == 0 then
        Msg((bank and "el banco" or "las bolsas") .. " ya esta ordenado.")
        return
    end
    queue = ops
    idx = 1
    lastOp = nil
    waited = 0
    timer = 0
    sortingBank = bank and true or false
    Msg("ordenando " .. (bank and "el banco" or "las bolsas") .. " (" .. table.getn(ops) .. " movimientos)...")
    frame:Show()
end

-- Funcion publica para que otros addons (p. ej. Bagnon) puedan ordenar
function OrdenaBolsas_Sort()
    Start()
end

function OrdenaBolsas_SortBank()
    Start(true)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("VARIABLES_LOADED")
loader:RegisterEvent("BANKFRAME_OPENED")
loader:RegisterEvent("BANKFRAME_CLOSED")
loader:SetScript("OnEvent", function()
    if event == "BANKFRAME_OPENED" then
        bankOpen = true
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = false
        if sortingBank then
            Stop("banco cerrado, proceso cancelado.")
        end
    elseif event == "VARIABLES_LOADED" then
        if not OrdenaBolsas_DB then OrdenaBolsas_DB = {} end
        if not OrdenaBolsas_DB.exclude then OrdenaBolsas_DB.exclude = {} end
    end
end)

SLASH_ORDENABOLSAS1 = "/ordenar"
SLASH_ORDENABOLSAS2 = "/sortbags"
SlashCmdList["ORDENABOLSAS"] = function(msg)
    msg = string.lower(msg or "")
    if not OrdenaBolsas_DB then OrdenaBolsas_DB = {} end
    if not OrdenaBolsas_DB.exclude then OrdenaBolsas_DB.exclude = {} end

    if msg == "stop" or msg == "parar" then
        Stop("cancelado.")
        return
    end

    local s, e, b = string.find(msg, "^excluir%s+(%-?%d+)")
    if b then
        b = tonumber(b)
        if OrdenaBolsas_DB.exclude[b] then
            OrdenaBolsas_DB.exclude[b] = nil
            Msg("bolsa " .. b .. " incluida.")
        else
            OrdenaBolsas_DB.exclude[b] = true
            Msg("bolsa " .. b .. " excluida.")
        end
        return
    end

    if msg == "estado" then
        local list = ""
        for bag = -1, 10 do
            if IsExcluded(bag) then list = list .. bag .. " " end
        end
        if list == "" then list = "ninguna" end
        Msg("bolsas excluidas: " .. list)
        return
    end

    if msg == "banco" or msg == "bank" then
        Start(true)
        return
    end

    Start()
end
