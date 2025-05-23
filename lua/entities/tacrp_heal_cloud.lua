ENT.Type = "anim"
ENT.Base = "base_entity"
ENT.PrintName = "Healing Gas Cloud"
ENT.Author = ""
ENT.Information = ""
ENT.Spawnable = false
ENT.AdminSpawnable = false

local smokeimages = {"particle/smokesprites_0001", "particle/smokesprites_0002", "particle/smokesprites_0003", "particle/smokesprites_0004", "particle/smokesprites_0005", "particle/smokesprites_0006", "particle/smokesprites_0007", "particle/smokesprites_0008", "particle/smokesprites_0009", "particle/smokesprites_0010", "particle/smokesprites_0011", "particle/smokesprites_0012", "particle/smokesprites_0013", "particle/smokesprites_0014", "particle/smokesprites_0015", "particle/smokesprites_0016"}

local function GetSmokeImage()
    return smokeimages[math.random(#smokeimages)]
end

local SmokeColor = Color(125, 25, 125)

ENT.Particles = nil
ENT.SmokeRadius = 256
ENT.SmokeColor = SmokeColor
ENT.BillowTime = 2.5
ENT.Life = 15

AddCSLuaFile()

function ENT:Initialize()
    if SERVER then
        self:SetModel( "models/weapons/w_eq_smokegrenade_thrown.mdl" )
        self:SetMoveType( MOVETYPE_NONE )
        self:SetSolid( SOLID_NONE )
        self:DrawShadow( false )
    else
        local emitter = ParticleEmitter(self:GetPos())

        self.Particles = {}

        local amt = 20

        for i = 1, amt do
            local smoke = emitter:Add(GetSmokeImage(), self:GetPos())
            smoke:SetVelocity( VectorRand() * 8 + (Angle(0, i * (360 / amt), 0):Forward() * 200) )
            smoke:SetStartAlpha( 0 )
            smoke:SetEndAlpha( 255 )
            smoke:SetStartSize( 0 )
            smoke:SetEndSize( self.SmokeRadius )
            smoke:SetRoll( math.Rand(-180, 180) )
            smoke:SetRollDelta( math.Rand(-0.2,0.2) )
            smoke:SetColor( self.SmokeColor.r, self.SmokeColor.g, self.SmokeColor.b )
            smoke:SetAirResistance( 75 )
            smoke:SetPos( self:GetPos() )
            smoke:SetCollide( true )
            smoke:SetBounce( 0.2 )
            smoke:SetLighting( false )
            smoke:SetNextThink( CurTime() + FrameTime() )
            smoke.bt = CurTime() + self.BillowTime
            smoke.dt = CurTime() + self.BillowTime + self.Life
            smoke.ft = CurTime() + self.BillowTime + self.Life + math.Rand(2.5, 5)
            smoke:SetDieTime(smoke.ft)
            smoke.life = self.Life
            smoke.billowed = false
            smoke.radius = self.SmokeRadius / 2
            smoke.offset_r = math.Rand(0, 100)
            smoke.offset_g = math.Rand(0, 100)
            smoke.offset_b = math.Rand(0, 100)
            smoke.pulsate_time = math.Rand(0.9, 3)
            smoke:SetThinkFunction( function(pa)
                if !pa then return end
                if !self then return end

                local prog = 1
                local alph = 0

                if pa.ft < CurTime() then
                    return
                elseif pa.dt < CurTime() then
                    local d = (CurTime() - pa.dt) / (pa.ft - pa.dt)

                    alph = 1 - d
                elseif pa.bt < CurTime() then
                    alph = 1
                else
                    local d = math.Clamp(pa:GetLifeTime() / (pa.bt - CurTime()), 0, 1)

                    prog = (-d ^ 2) + (2 * d)

                    alph = d
                end

                pa:SetColor(
                    SmokeColor.r + math.sin((CurTime() * pa.pulsate_time) + pa.offset_r) * 20,
                    SmokeColor.g + math.sin((CurTime() * pa.pulsate_time) + pa.offset_g) * 20,
                    SmokeColor.b + math.sin((CurTime() * pa.pulsate_time) + pa.offset_b) * 20
                )

                pa:SetEndSize( pa.radius * prog )
                pa:SetStartSize( pa.radius * prog )

                alph = math.Clamp(alph, 0, 1)

                pa:SetStartAlpha(35 * alph)
                pa:SetEndAlpha(35 * alph)

                pa:SetNextThink( CurTime() + FrameTime() )
            end )

            table.insert(self.Particles, smoke)
        end

        emitter:Finish()
    end

    self.dt = CurTime() + self.Life + self.BillowTime
end

function ENT:Think()

    if SERVER then
        if !self:GetOwner():IsValid() then self:Remove() return end
        local origin = self:GetPos() + Vector(0, 0, 16)

        for i, k in pairs(ents.FindInSphere(origin, self.SmokeRadius)) do
            if (k:IsPlayer() or k:IsNPC() or k:IsNextBot()) then
                local tr = util.TraceLine({
                    start = origin,
                    endpos = k:EyePos() or k:WorldSpaceCenter(),
                    filter = self,
                    mask = MASK_SOLID_BRUSHONLY
                })
                if tr.Fraction < 1 then continue end
                if k:IsPlayer() and (k.TacRPNextCanHealthGasTime or 0) <= CurTime() then
                    local ply = k
                    if ply:Health() < ply:GetMaxHealth() then
                        local amt = TacRP.ConVars["healnade_heal"]:GetInt()
                        local ret = {amt}
                        hook.Run("TacRP_MedkitHeal", self, self:GetOwner(), ply, ret)
                        amt = ret and ret[1] or amt
                        ply:SetHealth(math.min(ply:Health() + amt, ply:GetMaxHealth()))
                    elseif ply:Armor() > 0 and ply:Armor() <= ply:GetMaxArmor() and TacRP.ConVars["healnade_armor"]:GetInt() > 0 then
                        ply:SetArmor(math.min(ply:Armor() + TacRP.ConVars["healnade_armor"]:GetInt(), ply:GetMaxArmor()))
                    end
                    k.TacRPNextCanHealthGasTime = CurTime() + 0.19
                elseif !k:IsPlayer() and (k.TacRPNextCanHealthGasTime or 0) <= CurTime() then
                    if TacRP.EntityIsNecrotic(k) then
                        local dmginfo = DamageInfo()
                        dmginfo:SetAttacker(self:GetOwner() or self)
                        dmginfo:SetInflictor(self)
                        dmginfo:SetDamageType(DMG_NERVEGAS)
                        dmginfo:SetDamage(TacRP.ConVars["healnade_damage"]:GetInt())
                        k:TakeDamageInfo(dmginfo)
                    elseif k:Health() < k:GetMaxHealth() then
                        local amt = TacRP.ConVars["healnade_heal"]:GetInt()
                        local ret = {amt}
                        hook.Run("TacRP_MedkitHeal", self, self:GetOwner(), k, ret)
                        amt = ret and ret[1] or amt
                        k:SetHealth(math.min(k:Health() + amt, k:GetMaxHealth()))
                    end
                    k.TacRPNextCanHealthGasTime = CurTime() + 0.19
                end
            end
        end

        self:NextThink(CurTime() + 0.2)

        if self.dt < CurTime() then
            SafeRemoveEntity(self)
        end
    else
        if (self.NextEmitTime or 0) > CurTime() then return end

        local emitter = ParticleEmitter(self:GetPos())

        local smoke = emitter:Add("effects/spark", self:GetPos())
        smoke:SetVelocity( Vector(math.Rand(-1, 1), math.Rand(-1, 1), math.Rand(0, 1)) * 300 )
        smoke:SetStartAlpha( 255 )
        smoke:SetEndAlpha( 0 )
        smoke:SetStartSize( 0 )
        smoke:SetEndSize( 0 )
        smoke:SetRoll( math.Rand(-180, 180) )
        smoke:SetRollDelta( math.Rand(-32, 32) )
        smoke:SetColor( 255, 255, 255 )
        smoke:SetAirResistance( 100 )
        smoke:SetPos( self:GetPos() )
        smoke:SetCollide( true )
        smoke:SetBounce( 1 )
        smoke:SetLighting( false )
        smoke:SetDieTime(2)
        smoke:SetGravity(Vector(0, 0, -100))
        smoke:SetNextThink( CurTime() + FrameTime() )
        smoke.hl2 = CurTime() + 1
        smoke:SetThinkFunction( function(pa)
            if !pa then return end

            if pa.hl2 < CurTime() and !pa.alreadyhl then
                pa:SetStartSize(8)
                pa:SetEndSize(0)
                pa:SetLifeTime(0)
                pa:SetDieTime(math.Rand(0.25, 0.5))
                pa:SetVelocity(VectorRand() * 300)
                pa:SetGravity(Vector(0, 0, -200))
                pa:SetAirResistance( 200 )
                pa.alreadyhl = true
            else
                pa:SetNextThink( CurTime() + FrameTime() )
            end
        end )

        emitter:Finish()

        self.NextEmitTime = CurTime() + 0.02
    end

    return true
end

function ENT:Draw()
    return false
end