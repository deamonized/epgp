-- A library to make usage of coroutines in wow easier.
--
-- Check LibMapData for how to put this on wowace.
local MAJOR_VERSION = "LibCoroutine-1.0"
local MINOR_VERSION = 10000

local lib, oldMinor = LibStub:NewLibrary(MAJOR_VERSION, MINOR_VERSION)
if not lib then return end

local CallbackHandler = LibStub("CallbackHandler-1.0")

local AT = LibStub("AceTimer-3.0")

local function tissubset(t1, t2)
  for k,v in pairs(t1) do
    if t2[k] ~= v then
      if type(t2[k]) ~= "table" or type(v) ~= "table" then
        return false
      end

      if not tissubset(t2[k], v) then
        return false
      end
    end
  end
  return true
end

local function tisequal(t1, t2)
  return tissubset(t1, t2) and tissubset(t2, t1)
end

local function coresume(co, ...)
  local ok, err = coroutine.resume(co, ...)
  if not ok then
    geterrorhandler()(err)
  end
end

function lib:Condition(...)
  local co = coroutine.running()
  local expected_args = {...}
  local signalled = false
  local timed_out = false
  local timer_handle
  local cond = {}
  function cond.Signal()
    if not signalled then
      signalled = true
      AT:CancelTimer(timer_handle, true)
      timer_handle = nil
      if coroutine.status(co) == "suspended" then
        coresume(co, timed_out)
      end
    end
  end
  function cond.SignalIfMatching(...)
    if not signalled then
      if tisequal(expected_args, {...}) then
        cond.Signal()
      end
    end
  end
  function cond.Wait(timeout)
    if not signalled then
      if timeout then
        timer_handle = AT:ScheduleTimer(
          function()
            timed_out = true
            cond.Signal()
          end, timeout)
      end
      return coroutine.yield(co)
    end
    return timed_out
  end

  return cond
end

function lib:Yield()
  local cond = self:Condition()
  cond.Wait(0)
end

function lib:Sleep(t)
  local cond = self:Condition()
  cond.Wait(t)
end

function lib:RunAsync(fn, ...)
  local co = coroutine.create(fn)
  AT:ScheduleTimer(
    function(args) coresume(args[1], unpack(args, 2)) end,
    0,
    {co, ...})
end

function lib:WaitOnAny(timeout, ...)
  local barrier = self:Condition()

  for i=1,select('#', ...) do
    self:RunAsync(function(...)
                    local cond = select(i, ...)
                    cond.Wait(timeout)
                    barrier.Signal()
                  end, ...)
  end

  return barrier.Wait(timeout)
end

-- /run LibStub("LibCoroutine-1.0"):UnitTest()
function lib:UnitTest()
  function RunTests(i)
    print("running tests async. expecting 1 as arg. got ", i)

    local cond, cond2
    print("signal a condition before wait is called - no timeout")
    cond = lib:Condition()
    cond.Signal()
    print("done", "[timed_out=", cond.Wait(), "]")

    print("signal a condition before wait is called - with timeout")
    cond = lib:Condition()
    cond.Signal()
    cond.Wait(1)
    print("done", "[timed_out=", cond.Wait(1), "]")

    print("signal a condition after wait is called - no timeout")
    cond = lib:Condition()
    AT:ScheduleTimer(cond.Signal, 0)
    print("done", "[timed_out=", cond.Wait(), "]")

    print("signal a condition after wait is called - with timeout")
    cond = lib:Condition()
    AT:ScheduleTimer(cond.Signal, 0)
    print("done", "[timed_out=", cond.Wait(1), "]")

    print("signal a condition with a matcher - args match/no timeout")
    cond = lib:Condition(1, 2)
    cond.SignalIfMatching(1, 2)
    print("done", "[timed_out=", cond.Wait(1), "]")

    print("signal a condition with a matcher - args do not match/timeout")
    cond = lib:Condition(1, 2)
    cond.SignalIfMatching(1)
    print("done", "[timed_out=", cond.Wait(1), "]")

    print("wait on two conditions and wait for timeout")
    cond = lib:Condition()
    cond2 = lib:Condition()
    print("done", "[timed_out=", lib:WaitOnAny(1, cond, cond2), "]")

    print("wait on two conditions and signal one")
    cond = lib:Condition()
    cond2 = lib:Condition()
    AT:ScheduleTimer(cond.Signal, 0)
    print("done", "[timed_out=", lib:WaitOnAny(1, cond, cond2), "]")
  end

  lib:RunAsync(RunTests, 1)
end
