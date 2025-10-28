local Storage = require("buffergolf.session.storage")
local assert = require("luassert")

describe("session storage", function()
  -- Mock session objects
  local session1, session2

  before_each(function()
    -- Clear any existing sessions
    Storage.clear({ origin_buf = 1, practice_buf = 2 })
    Storage.clear({ origin_buf = 3, practice_buf = 4 })

    -- Create mock sessions
    session1 = {
      origin_buf = 1,
      practice_buf = 2,
      mode = "typing",
    }

    session2 = {
      origin_buf = 3,
      practice_buf = 4,
      mode = "golf",
    }
  end)

  describe("store and get", function()
    it("stores and retrieves session by origin buffer", function()
      Storage.store(session1)

      local retrieved = Storage.get(1)
      assert.equal(session1, retrieved)
      assert.equal("typing", retrieved.mode)
    end)

    it("stores and retrieves session by practice buffer", function()
      Storage.store(session1)

      local retrieved = Storage.get(2)
      assert.equal(session1, retrieved)
      assert.equal("typing", retrieved.mode)
    end)

    it("handles multiple sessions without interference", function()
      Storage.store(session1)
      Storage.store(session2)

      assert.equal(session1, Storage.get(1))
      assert.equal(session1, Storage.get(2))
      assert.equal(session2, Storage.get(3))
      assert.equal(session2, Storage.get(4))

      assert.not_equal(Storage.get(1), Storage.get(3))
    end)
  end)

  describe("is_active", function()
    it("returns true for stored session buffers", function()
      Storage.store(session1)

      assert.is_true(Storage.is_active(1))
      assert.is_true(Storage.is_active(2))
    end)

    it("returns false for non-existent buffers", function()
      assert.is_false(Storage.is_active(999))
    end)
  end)

  describe("clear", function()
    it("removes session from both lookup tables", function()
      Storage.store(session1)
      Storage.clear(session1)

      assert.is_nil(Storage.get(1))
      assert.is_nil(Storage.get(2))
      assert.is_false(Storage.is_active(1))
      assert.is_false(Storage.is_active(2))
    end)

    it("only clears specified session", function()
      Storage.store(session1)
      Storage.store(session2)

      Storage.clear(session1)

      assert.is_nil(Storage.get(1))
      assert.is_nil(Storage.get(2))

      assert.equal(session2, Storage.get(3))
      assert.equal(session2, Storage.get(4))
    end)
  end)

  describe("by_practice", function()
    it("retrieves session by practice buffer only", function()
      Storage.store(session1)

      assert.equal(session1, Storage.by_practice(2))
      assert.is_nil(Storage.by_practice(1))
      assert.is_nil(Storage.by_practice(999))
    end)
  end)

  describe("nil/non-existent handling", function()
    it("returns nil for non-existent buffers", function()
      Storage.store(session1)

      assert.is_nil(Storage.get(999))
    end)
  end)
end)
