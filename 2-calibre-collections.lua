-- SPDX-FileCopyrightText: 2026 Sayantan Santra <sayantan.santra689@gmail.com>
-- SPDX-License-Identifier: MIT
-- Sync KOReader collections from Calibre's #collections custom column.
-- https://github.com/SinTan1729/koreader-patches

local userpatch = require("userpatch")
local ReadCollection = require("readcollection")
local FileManagerCollection = require("apps/filemanager/filemanagercollection")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")

local json
do
    local ok
    ok, json = pcall(require, "json")
    if not ok then
        ok, json = pcall(require, "rapidjson")
    end
    if not ok then
        logger.err("Calibre Collections: no JSON library found")
        return
    end
end

-- constants
local METADATA_FILE = "/mnt/onboard/metadata.calibre"
local LIBRARY_ROOT = "/mnt/onboard"
local MARKER = "\u{1F4A1}"
local SETTINGS_FILE =
    DataStorage:getSettingsDir() .. "/calibre_collections.lua"

-- state
local settings = LuaSettings:open(SETTINGS_FILE)
local managed =
    settings:readSetting("managed_collections", {})
local startup_done = false

-- persistence
local function saveState()
    settings:saveSetting(
        "managed_collections",
        managed
    )
    settings:flush()
end

-- marker support
local function isManaged(name)
    return managed[name] == true
end
local orig_getCollMarker = FileManagerCollection.getCollMarker

function FileManagerCollection.getCollMarker(name)
    local marker = orig_getCollMarker(name)
    if isManaged(name) then
        marker = marker and
            (marker .. " " .. MARKER)
            or MARKER
    end
    return marker
end

-- collection helpers
local function collectionExists(name)
    return ReadCollection.coll[name]
end

local function createCollection(name)
    if collectionExists(name) then
        return true
    end

    logger.info(
        "Calibre Collections: Creating collection:",
        name
    )

    ReadCollection:addCollection(name)
    ReadCollection:write({ [name] = true })
end

local function ensureCollection(name)
    if collectionExists(name) then
        return
    end
    createCollection(name)
end

local function collectionContains(filepath, collection)
    return ReadCollection:isFileInCollection(
        filepath,
        collection
    )
end

local function addBook(filepath, collection)
    if collectionContains(filepath, collection) then
        return
    end

    logger.info(
        "Calibre Collections: Adding",
        filepath, "to", collection
    )

    ReadCollection:addItem(
        filepath,
        collection
    )
end

local function removeBook(filepath, collection)
    if not collectionContains(filepath, collection) then
        return
    end

    logger.info(
        "Calibre Collections: Removing",
        filepath, "from", collection
    )

    ReadCollection:removeItem(
        filepath,
        collection,
        true
    )
end

local function removeManagedCollection(name)
    if not isManaged(name) then
        return
    end
    ReadCollection:removeCollection(name)

    logger.info(
        "Calibre Collections: Removing collection:",
        name
    )

    managed[name] = nil
    ReadCollection:write({ [name] = true })
end


-- metadata parsing
local function loadMetadata()
    local f = io.open(METADATA_FILE, "rb")
    if not f then
        logger.warn(
            "Calibre Collections: metadata.calibre not found"
        )
        return nil
    end

    local text = f:read("*a")
    f:close()

    local ok, data = pcall(function()
        return json.decode(text)
    end)

    if not ok then
        logger.err(
            "Calibre Collections: JSON parse failed"
        )
        return nil
    end

    return data
end

local function getBookCollections(book)
    local md = book.user_metadata
    if not md then
        return nil
    end

    local c = md["#collections"]
    if not c then
        return nil
    end
    return c["#value#"]
end

local function getBookPath(book)
    local lpath = book.lpath
    if not lpath then
        return nil
    end
    return LIBRARY_ROOT .. "/" .. lpath
end

-- sync
local function buildDesiredMembership(metadata)
    local desired = {}
    for _, book in ipairs(metadata) do
        local path = getBookPath(book)
        if path and lfs.attributes(path) then
            local collections =
                getBookCollections(book)

            if collections then
                for _, collection in ipairs(collections) do
                    desired[collection] =
                        desired[collection] or {}

                    desired[collection][path] = true
                end
            end
        end
    end

    return desired
end

local function syncManagedCollection(
    collection_name,
    desired_members
)
    if next(desired_members) == nil then
        removeManagedCollection(collection_name)
        return
    end
    ensureCollection(collection_name)
    local current = {}
    local coll = ReadCollection.coll[collection_name]
    if coll then
        for filepath in pairs(coll) do
            current[filepath] = true
        end
    end

    -- additions
    for filepath in pairs(desired_members) do
        if not current[filepath] then
            addBook(
                filepath,
                collection_name
            )
        end
    end

    -- removals
    for filepath in pairs(current) do
        if not desired_members[filepath] then
            removeBook(
                filepath,
                collection_name
            )
        end
    end
end

local function runSync()
    local metadata = loadMetadata()
    if not metadata then
        return
    end

    local desired =
        buildDesiredMembership(metadata)

    -- create newly discovered collections
    for collection_name in pairs(desired) do
        if not collectionExists(collection_name) then
            createCollection(collection_name)
            managed[collection_name] = true
        end
    end

    saveState()

    -- sync only managed collections
    for collection_name in pairs(managed) do
        local desired_members =
            desired[collection_name] or {}

        syncManagedCollection(
            collection_name,
            desired_members
        )
        ReadCollection:write({ [collection_name] = true })
    end

    saveState()

    logger.info(
        "Calibre Collections: sync complete"
    )
end

-- startup
local function startup()
    if startup_done then
        return
    end


    startup_done = true

    local ok, err = pcall(runSync)

    if not ok then
        logger.err(
            "Calibre Collections failed:",
            err
        )
    end
end

-- hook
userpatch.registerPatchPluginFunc(
    "coverbrowser",
    function()
        startup()
    end
)

logger.info(
    "Calibre Collections were successfully created and/or synced."
)

-- Prevent KOReader's default folder syncing for smart collections
local orig_ReadCollection_updateCollectionFromFolder = ReadCollection.updateCollectionFromFolder
function ReadCollection:updateCollectionFromFolder(collection_name, folders, is_showing)
    if isManaged(collection_name) then
        return 0
    end
    return orig_ReadCollection_updateCollectionFromFolder(self, collection_name, folders, is_showing)
end
