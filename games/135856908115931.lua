-- ============================================================
--  games/135856908115931.lua  --  MVS Duels (main "Murderers VS Sheriffs")
--
--  Same community + same RE/GunKill flow as the 1v1 place, so just re-dispatch
--  to the canonical module. That module guards on the remote existing, so if
--  this place ever diverges it degrades to a notice instead of misfiring.
-- ============================================================
local ctx = ({ ... })[1]
return ctx.load("games/124848751642883.lua")(ctx)
