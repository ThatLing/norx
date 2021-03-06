NORX = {}

NORX.HEADER_TAG  = 0x01
NORX.PAYLOAD_TAG = 0x02
NORX.TRAILER_TAG = 0x04
NORX.FINAL_TAG   = 0x08
NORX.BRANCH_TAG  = 0x10
NORX.MERGE_TAG   = 0x20

-- Changing to 64-bit should be possible but will require some work
NORX.Rounds = 4
NORX.W = 32
NORX.WBYTE = NORX.W / 8		-- 4
NORX.B = NORX.W * 16
NORX.C = NORX.W * 4
NORX.R = NORX.B - NORX.C
NORX.RBYTE = NORX.R / 8		-- 48
NORX.RWORD = NORX.R / 32	-- 12

local string_sub = string.sub
local string_char = string.char
local string_byte = string.byte
local string_len = string.len
local string_rep = string.rep
local table_concat = table.concat
local bit_bxor = bit.bxor
local bit_band = bit.band
local bit_rshift = bit.rshift
local bit_lshift = bit.lshift
local bit_ror = bit.ror
local bit_rol = bit.rol



local function G(s, a, b, c, d)
	s[a] = bit_bxor(bit_bxor(s[a], s[b]), bit_lshift(bit_band(s[a], s[b]), 1))
	s[d] = bit_ror(bit_bxor(s[a], s[d]), 8)
	
	s[c] = bit_bxor(bit_bxor(s[c], s[d]), bit_lshift(bit_band(s[c], s[d]), 1))
	s[b] = bit_ror(bit_bxor(s[b], s[c]), 11)
	
	s[a] = bit_bxor(bit_bxor(s[a], s[b]), bit_lshift(bit_band(s[a], s[b]), 1))
	s[d] = bit_ror(bit_bxor(s[a], s[d]), 16)
	
	s[c] = bit_bxor(bit_bxor(s[c], s[d]), bit_lshift(bit_band(s[c], s[d]), 1))
	s[b] = bit_ror(bit_bxor(s[b], s[c]), 31)
end
NORX.G = G

local function F(s)
	G(s, 1, 5, 9,  13)
	G(s, 2, 6, 10, 14)
	G(s, 3, 7, 11, 15)
	G(s, 4, 8, 12, 16)
		
	G(s, 1, 6, 11, 16)
	G(s, 2, 7, 12, 13)
	G(s, 3, 8, 9,  14)
	G(s, 4, 5, 10, 15)
end
NORX.F = F

local function permute(s)
	for i = 1, NORX.Rounds do
		F(s)
	end
end
NORX.permute = permute

local function littleendian(b, i)
	return 		b[i] 			+ 
		bit_rol(b[i + 1], 8)  	+ 
		bit_rol(b[i + 2], 16) 	+ 
		bit_rol(b[i + 3], 24)
end
NORX.littleendian = littleendian

local function inv_littleendian(b, char)
	local x0 = bit_band(		b, 			0xFF)
	local x1 = bit_band(bit_ror(b, 8 ), 	0xFF)
	local x2 = bit_band(bit_ror(b, 16), 	0xFF)
	local x3 = bit_band(bit_ror(b, 24), 	0xFF)
	
	if char then
		x0 = string_char(x0)
		x1 = string_char(x1)
		x2 = string_char(x2)
		x3 = string_char(x3)
	end
	
	return x0, x1, x2, x3
end
NORX.inv_littleendian = inv_littleendian


local u13 = bit_bxor(0x335463EB, 32)
local u14 = bit_bxor(0xF994220B, 4)
local u15 = bit_bxor(0xBE0BF5C9, 1)
local u16 = bit_bxor(0xD7C49104, 128)

local function initialise(k, n)
	local s = {}
	
	k = { string_byte(k, 1, -1) }
	n = { string_byte(n, 1, -1) }

	s[1] = littleendian(n, 1)
	s[2] = littleendian(n, 5)
	s[3] = littleendian(n, 9)
	s[4] = littleendian(n, 13)
	
	
	local k0 = littleendian(k, 1)
	s[5] = k0

	local k1 = littleendian(k, 5)
	s[6] = k1
	
	local k2 = littleendian(k, 9)
	s[7] = k2
	
	local k3 = littleendian(k, 13)
	s[8] = k3
	
	
	s[9]  = 0xA3D8D930
	s[10] = 0x3FA8B72C
	s[11] = 0xED84EB49
	s[12] = 0xEDCA4787
	s[13] = u13
	s[14] = u14
	s[15] = u15
	s[16] = u16
	
	
	permute(s)
	
	s[13] = bit_bxor(s[13], k0)
	s[14] = bit_bxor(s[14], k1)
	s[15] = bit_bxor(s[15], k2)
	s[16] = bit_bxor(s[16], k3)
	
	return s
end
NORX.initialise = initialise

local function pad(str)
	local str_len = string_len(str)
	
	if str_len == NORX.RBYTE - 1 then return str .. "\x81" end
	
	return str .. "\x01" .. string_rep("\x00", NORX.RBYTE - 2 - str_len) .. "\x80"
end
NORX.pad = pad

local function NORX.absorb_block(s, a, idx, v)
	s[16] = bit_bxor(s[16], v)
	permute(s)

	local m = { string_byte(a, idx, idx + 12 * NORX.WBYTE) }

	for i = 0, NORX.RWORD - 1 do
		s[i + 1] = bit_bxor(s[i + 1], littleendian(m, 1 + i * NORX.WBYTE))
	end
	
	return s
end
NORX.absorb_block = absorb_block

local function absorb_lastblock(s, str, v)
	absorb_block(s, pad(str), 1, v)
end
NORX.absorb_lastblock = absorb_lastblock

local function absorb_data(s, a, v)
	local str_len = string_len(a)
	local i = 1
	
	if str_len > 0 then
		while str_len >= NORX.RBYTE do
			absorb_block(s, a, i, v)
			
			str_len = str_len - NORX.RBYTE
			i = i + NORX.RBYTE
		end

		absorb_lastblock(s, string_sub(a, i), v)
	end
	
	return s
end
NORX.absorb_data = absorb_data

local function encrypt_block(s, m, out, idx)
	s[16] = bit_bxor(s[16], NORX.PAYLOAD_TAG)
	permute(s)
	
	local d = { string_byte(m, idx, idx + 12 * NORX.WBYTE) }

	for i = 0, NORX.RWORD - 1 do
		local c  = bit_bxor(s[i + 1], littleendian(d, 1 + i * NORX.WBYTE))
		
		local outSize = #out
		out[outSize + 1], out[outSize + 2], out[outSize + 3], out[outSize + 4] = inv_littleendian(c, true)
		
		s[i + 1] = c
	end
end
NORX.encrypt_block = encrypt_block

local function encrypt_lastblock(s, str, out)
	local str_len = string_len(str)
	local temp = {}
	
	encrypt_block(s, pad(str), temp, 1)
	
	for i = 1, str_len do
		out[#out + 1] = temp[i]
	end
end
NORX.encrypt_lastblock = encrypt_lastblock

local function decrypt_block(s, c, out, idx)
	s[16] = bit_bxor(s[16], NORX.PAYLOAD_TAG)
	permute(s)
	
	local d = { string_byte(c, idx, idx + 12 * NORX.WBYTE) }

	for i = 0, NORX.RWORD - 1 do
		local c = NORX.littleendian(d, 1 + i * NORX.WBYTE)
		
		local outSize = #out
		out[outSize + 1], out[outSize + 2], out[outSize + 3], out[outSize + 4] = inv_littleendian(bit_bxor(s[i + 1], c), true)
		
		s[i + 1] = c
	end
end
NORX.decrypt_block = decrypt_block

local function decrypt_lastblock(s, str, out)
	local str_len = string_len(str)
	local temp = {}
	
	s[16] = bit_bxor(s[16], NORX.PAYLOAD_TAG)
	permute(s)
	
	for i = 1, NORX.RWORD do
		local outSize = #temp
		temp[outSize + 1], temp[outSize + 2], temp[outSize + 3], temp[outSize + 4] = inv_littleendian(s[i])
	end
	
	for i = 1, str_len do
		temp[i] = string_byte(str, i, i)
	end
	
	temp[str_len + 1] = bit_bxor(temp[str_len + 1], 0x01)
	temp[NORX.RBYTE] = bit_bxor(temp[NORX.RBYTE], 0x80)
	
	for i = 0, NORX.RWORD - 1 do
		local idx = 1 + i * NORX.WBYTE
		
		local c = littleendian(temp, idx)

		temp[idx], temp[idx + 1], temp[idx + 2], temp[idx + 3] = inv_littleendian(bit_bxor(s[i + 1], c), true)
		
		s[i + 1] = c
	end
	
	for i = 1, str_len do
		out[#out + 1] = temp[i]
	end
end
NORX.decrypt_lastblock = decrypt_lastblock

local function encrypt_data(s, m)
	local str_len = string_len(m)
	local out = {}
	local i = 1
	
	
	if str_len > 0 then
		while str_len >= NORX.RBYTE do
			encrypt_block(s, m, out, i)
			
			str_len = str_len - NORX.RBYTE
			i = i + NORX.RBYTE
		end
		
		encrypt_lastblock(s, string_sub(m, i), out)
	end
	
	return out
end
NORX.encrypt_data = encrypt_data

local function decrypt_data(s, m)
	local str_len = string_len(m)
	local out = {}
	local i = 1
	
	
	if str_len > 0 then
		while str_len >= NORX.RBYTE do
			decrypt_block(s, m, out, i)
			
			str_len = str_len - NORX.RBYTE
			i = i + NORX.RBYTE
		end
		
		decrypt_lastblock(s, string_sub(m, i), out)
	end
	
	return out
end
NORX.decrypt_data = decrypt_data

local function finalise(s, k)
	s[16] = bit_bxor(s[16], NORX.FINAL_TAG)
	
	permute(s)
	
	k = { string_byte(k, 1, -1) }
	
	local k0 = littleendian(k, 1)
	local k1 = littleendian(k, 5)
	local k2 = littleendian(k, 9)	
	local k3 = littleendian(k, 13)
	
	s[13] = bit_bxor(s[13], k0)
	s[14] = bit_bxor(s[14], k1)
	s[15] = bit_bxor(s[15], k2)
	s[16] = bit_bxor(s[16], k3)
	
	permute(s)
	
	s[13] = bit_bxor(s[13], k0)
	s[14] = bit_bxor(s[14], k1)
	s[15] = bit_bxor(s[15], k2)
	s[16] = bit_bxor(s[16], k3)
	
	
	local tag = ""
	tag = tag .. string_char(inv_littleendian(s[13]))
	tag = tag .. string_char(inv_littleendian(s[14]))
	tag = tag .. string_char(inv_littleendian(s[15]))
	tag = tag .. string_char(inv_littleendian(s[16]))
	
	return tag
end
NORX.finalise = finalise

local function verify_tag(tag1, tag2)
	return tag1 == tag2
end
NORX.verify_tag = verify_tag

local function AEADEnc(k, n, a, m, z)
	if string_len(k) ~= 16 then
		error("k must by 16 bytes!")
	end
	
	if string_len(n) ~= 16 then
		error("n must by 16 bytes!")
	end
	
	local s, out, tag
	
	s = initialise(k, n)
	s = absorb_data(s, a, NORX.HEADER_TAG)
	out = encrypt_data(s, m)
	s = absorb_data(s, z, NORX.TRAILER_TAG)
	tag = finalise(s, k)
	
	
	for i = 1, #tag do
		out[#out + 1] = tag[i]
	end
	
	return table_concat(out)
end
NORX.AEADEnc = AEADEnc

local function AEADDec(k, n, a, c, z)
	local s, out
	local str_len = string_len(c)
	
	local tag1 = string_sub(c, str_len - 15)
	c = string_sub(c, 1, str_len - 16)


	s = initialise(k, n)
	s = absorb_data(s, a, NORX.HEADER_TAG)
	out = decrypt_data(s, c)
	s = absorb_data(s, z, NORX.TRAILER_TAG)
	local tag2 = finalise(s, k)

	
	if not verify_tag(tag1, tag2) then
		out = nil
		s = nil
		tag1 = nil
		tag2 = nil
		
		return nil, "tag mismatch"
	end
	
	
	return table_concat(out)
end
NORX.AEADDec = AEADDec
