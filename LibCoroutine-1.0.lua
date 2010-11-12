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

function lib:Notification(...)
  local co
  local expected_args = {...}
  local timer_handle
  local ret  -- 0 means timed out. N means Nth cond was signalled.
  local hook  -- Used for WaitOnAny.
  local notif = {}

  local function SignalN(n)
    return function()
             if ret then return end
             ret = n
             AT:CancelTimer(timer_handle, true)
             timer_handler = nil
             if notif._hook then notif._hook() end
             if co and coroutine.status(co) == "suspended" then
               coresume(co, ret)
             end
           end
  end

  function notif.Signalled()
    return ret ~= nil
  end

  notif.Signal = SignalN(1)

  function notif.SignalIfMatching(...)
    if ret then return end
    if tisequal(expected_args, {...}) then
      notif.Signal()
    end
  end
  function notif.Wait(timeout)
    if ret then return ret end
    co = coroutine.running()
    if timeout then
      timer_handle = AT:ScheduleTimer(SignalN(0), timeout)
    end
    return coroutine.yield(co)
  end
  function notif.WaitOnAny(timeout, ...)
    if ret then return ret end
    for i=1,select('#', ...) do
      local n = select(i, ...)
      if n.Signalled() then return i+1 end
    end
    co = coroutine.running()
    for i=1,select('#', ...) do
      select(i, ...)._hook = SignalN(i+1)
    end
    return notif.Wait(timeout)
  end

  return notif
end

function lib:Yield()
  local notif = self:Notification()
  notif.Wait(0)
end

function lib:Sleep(t)
  local notif = self:Notification()
  notif.Wait(t)
end

function lib:RunAsync(fn, ...)
  local co = coroutine.create(fn)
  AT:ScheduleTimer(
    function(args) coresume(args[1], unpack(args, 2)) end,
    0,
    {co, ...})
end

function lib:WaitOnAny(timeout, notif, ...)
  return notif.WaitOnAny(timeout, ...)
end

-- /run LibStub("LibCoroutine-1.0"):UnitTest()
function lib:UnitTest()
  function RunTests(i)
    print("running tests async. expecting 1 as arg. got ", i)

    local notif, notif2
    print("signal a notification before wait is called - no timeout")
    notif = lib:Notification()
    notif.Signal()
    print("done", "[ret=", notif.Wait(), "]")

    print("signal a notification before wait is called - with timeout")
    notif = lib:Notification()
    notif.Signal()
    notif.Wait(1)
    print("done", "[ret=", notif.Wait(1), "]")

    print("signal a notification after wait is called - no timeout")
    notif = lib:Notification()
    AT:ScheduleTimer(notif.Signal, 0)
    print("done", "[ret=", notif.Wait(), "]")

    print("signal a notification with SignalIfMatching")
    notif = lib:Notification()
    AT:ScheduleTimer(notif.SignalIfMatching, 0, 1)
    print("done", "[ret=", notif.Wait(1), "]")

    print("signal a notification after wait is called - with timeout")
    notif = lib:Notification()
    AT:ScheduleTimer(notif.Signal, 0)
    print("done", "[ret=", notif.Wait(1), "]")

    print("signal a notification with a matcher - args match/no timeout")
    notif = lib:Notification(1, 2)
    notif.SignalIfMatching(1, 2)
    print("done", "[ret=", notif.Wait(1), "]")

    print("signal a notification with a matcher - args do not match/timeout")
    notif = lib:Notification(1, 2)
    notif.SignalIfMatching(1)
    print("done", "[ret=", notif.Wait(1), "]")

    print("wait on two notifications and wait for timeout")
    notif = lib:Notification()
    notif2 = lib:Notification()
    print("done", "[ret=", lib:WaitOnAny(1, notif, notif2), "]")

    print("wait on two notifications and signal one before wait is called")
    notif = lib:Notification()
    notif2 = lib:Notification()
    notif2.Signal()
    print("done", "[ret=", lib:WaitOnAny(1, notif, notif2), "]")

    print("wait on two notifications and signal one after wait is called")
    notif = lib:Notification()
    notif2 = lib:Notification()
    AT:ScheduleTimer(notif2.Signal, 0)
    print("done", "[ret=", lib:WaitOnAny(1, notif, notif2), "]")
  end

  lib:RunAsync(RunTests, 1)
end
