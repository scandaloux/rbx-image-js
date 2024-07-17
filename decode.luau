local indexes, indexCount = {}, 1;

for index = 65, 90 do indexes[index] = indexCount; indexCount = indexCount + 1; end;
for index = 97, 122 do  indexes[index] = indexCount; indexCount = indexCount + 1;  end;
for index = 48, 57 do  indexes[index] = indexCount; indexCount = indexCount + 1;  end;
indexes[43] = indexCount;
indexes[47] = indexCount + 1;

local bit32_rshift, bit32_lshift, bit32_band = bit32.rshift, bit32.lshift, bit32.band;
local string_byte, string_char, string_sub = string.byte, string.char, string.sub;
local buffer_fromstring, buffer_readu8 = buffer.fromstring, buffer.readu8;
local table_insert, table_concat = table.insert, table.concat;

function base64decode(input)
	local output = {}
	local length = 0

	for index = 1, #input, 4 do
		local c1, c2, c3, c4 = string_byte(input, index, index + 3)
		local i1, i2, i3, i4 = indexes[c1] - 1, indexes[c2] - 1, (indexes[c3] or 1) - 1, (indexes[c4] or 1) - 1
		local a, b, c = bit32_lshift(i1, 2) + bit32_rshift(i2, 4), bit32_lshift(bit32_band(i2, 15), 4) + bit32_rshift(i3, 2), bit32_lshift(bit32_band(i3, 3), 6) + i4
		length = length + 1
		output[length] = a
		if c1 ~= 61 then
			length = length + 1
			output[length] = b
		end
		if c1 ~= 61 then
			length = length + 1
			output[length] = c
		end
	end

	local newOutput = {}
	local newLength = 0
	local indexAdd4096Sub1

	for index = 1, length, 4096 do
		newLength = newLength + 1
		indexAdd4096Sub1 = index + 4096 - 1
		newOutput[newLength] = string_char(unpack(output, index, indexAdd4096Sub1 > length and length or indexAdd4096Sub1))
	end

	return table_concat(newOutput)
end

local _pow2, _reverse_bits_tbl, _byte_to_char = {}, {}, {}
local _fix_block_literal_huffman_bitlen, _fix_block_dist_huffman_bitlen

local _literal_deflate_code_to_base_len = {
	3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
	35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258,
}
local _literal_deflate_code_to_extra_bitlen = {
	0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
	3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
}
local _dist_deflate_code_to_base_dist = {
	[0] = 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
	257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
	8193, 12289, 16385, 24577,
}
local _dist_deflate_code_to_extra_bitlen = {
	[0] = 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
	7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13,
}
local _rle_codes_huffman_bitlen_order = {16, 17, 18,
	0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
}

local function getHuffmanForDecode(huffman_bitlens, max_symbol, max_bitlen)
	local huffman_bitlen_counts = {}
	local min_bitlen = max_bitlen
	for symbol = 0, max_symbol do
		local bitlen = huffman_bitlens[symbol] or 0
		min_bitlen = (bitlen > 0 and bitlen < min_bitlen) and bitlen or min_bitlen
		huffman_bitlen_counts[bitlen] = (huffman_bitlen_counts[bitlen] or 0)+1
	end

	if huffman_bitlen_counts[0] == max_symbol+1 then
		return 0, huffman_bitlen_counts, {}, 0 
	end

	local left = 1
	for len = 1, max_bitlen do
		left = left * 2
		left = left - (huffman_bitlen_counts[len] or 0)
		if left < 0 then return left end
	end

	local offsets = {}
	offsets[1] = 0
	for len = 1, max_bitlen-1 do
		offsets[len + 1] = offsets[len] + (huffman_bitlen_counts[len] or 0)
	end

	local huffman_symbols = {}
	for symbol = 0, max_symbol do
		local bitlen = huffman_bitlens[symbol] or 0
		if bitlen ~= 0 then
			local offset = offsets[bitlen]
			huffman_symbols[offset] = symbol
			offsets[bitlen] = offsets[bitlen] + 1
		end
	end

	return left, huffman_bitlen_counts, huffman_symbols, min_bitlen
end

local function getHuffmanCodeFromBitlen(bitlen_counts, symbol_bitlens, max_symbol, max_bitlen)
	local huffman_code = 0
	local next_codes = {}
	local symbol_huffman_codes = {}
	for bitlen = 1, max_bitlen do
		huffman_code = (huffman_code+(bitlen_counts[bitlen-1] or 0))*2
		next_codes[bitlen] = huffman_code
	end
	for symbol = 0, max_symbol do
		local bitlen = symbol_bitlens[symbol]
		if bitlen then
			huffman_code = next_codes[bitlen]
			next_codes[bitlen] = huffman_code + 1

			if bitlen <= 9 then
				symbol_huffman_codes[symbol] = _reverse_bits_tbl[bitlen][huffman_code]
			else
				local reverse = 0
				for _ = 1, bitlen do
					reverse = reverse - reverse%2 + (((reverse%2==1) or (huffman_code % 2) == 1) and 1 or 0)
					huffman_code = (huffman_code-huffman_code%2)/2
					reverse = reverse*2
				end
				symbol_huffman_codes[symbol] = (reverse-reverse%2)/2
			end
		end
	end
	return symbol_huffman_codes
end

local pow = 1; for i = 0, 32 do _pow2[i] = pow; pow = pow * 2; end

for i = 1, 9 do
	_reverse_bits_tbl[i] = {}
	for j=0, _pow2[i+1]-1 do
		local reverse = 0
		local value = j
		for _ = 1, i do
			reverse = reverse - reverse%2 + (((reverse%2==1) or (value % 2) == 1) and 1 or 0)
			value = (value-value%2)/2
			reverse = reverse * 2
		end
		_reverse_bits_tbl[i][j] = (reverse-reverse%2)/2
	end
end

do
	_fix_block_literal_huffman_bitlen = {}
	for sym=0, 143 do _fix_block_literal_huffman_bitlen[sym] = 8 end
	for sym=144, 255 do _fix_block_literal_huffman_bitlen[sym] = 9 end
	for sym=256, 279 do _fix_block_literal_huffman_bitlen[sym] = 7 end
	for sym=280, 287 do _fix_block_literal_huffman_bitlen[sym] = 8 end

	_fix_block_dist_huffman_bitlen = {}
	for dist=0, 31 do _fix_block_dist_huffman_bitlen[dist] = 5 end
	local status
	status, _fix_block_literal_huffman_bitlen_count, _fix_block_literal_huffman_to_deflate_code = getHuffmanForDecode(_fix_block_literal_huffman_bitlen, 287, 9)
	status, _fix_block_dist_huffman_bitlen_count, _fix_block_dist_huffman_to_deflate_code = getHuffmanForDecode(_fix_block_dist_huffman_bitlen, 31, 5)
	_fix_block_literal_huffman_code = getHuffmanCodeFromBitlen(_fix_block_literal_huffman_bitlen_count, _fix_block_literal_huffman_bitlen, 287, 9)
	_fix_block_dist_huffman_code = getHuffmanCodeFromBitlen(_fix_block_dist_huffman_bitlen_count, _fix_block_dist_huffman_bitlen, 31, 5)
end

for i = 0, 255 do _byte_to_char[i] = string_char(i) end

local function createReader(input_string)
	local input = input_string
	local input_strlen = #input_string
	local input_next_byte_pos = 1
	local cache_bitlen = 0
	local cache = 0

	local function readBits(bitlen)
		local rshift_mask = _pow2[bitlen]
		local code
		if bitlen <= cache_bitlen then
			code = cache % rshift_mask
			cache = (cache - code) / rshift_mask
			cache_bitlen = cache_bitlen - bitlen
		else
			local lshift_mask = _pow2[cache_bitlen]
			local byte1, byte2, byte3, byte4 = string_byte(input, input_next_byte_pos, input_next_byte_pos+3)
			cache = cache + ((byte1 or 0)+(byte2 or 0)*256 + (byte3 or 0)*65536+(byte4 or 0)*16777216)*lshift_mask
			input_next_byte_pos = input_next_byte_pos + 4
			cache_bitlen = cache_bitlen + 32 - bitlen
			code = cache % rshift_mask
			cache = (cache - code) / rshift_mask
		end
		return code
	end

	local function readBytes(bytelen, buffer, buffer_size)
		assert(cache_bitlen % 8 == 0)

		local byte_from_cache = (cache_bitlen/8 < bytelen) and (cache_bitlen/8) or bytelen
		for _=1, byte_from_cache do
			local byte = cache % 256
			buffer_size = buffer_size + 1
			buffer[buffer_size] = string_char(byte)
			cache = (cache - byte) / 256
		end
		cache_bitlen = cache_bitlen - byte_from_cache*8
		bytelen = bytelen - byte_from_cache
		if (input_strlen - input_next_byte_pos - bytelen + 1) * 8 + cache_bitlen < 0 then return -1 end
		for i=input_next_byte_pos, input_next_byte_pos+bytelen-1 do
			buffer_size = buffer_size + 1
			buffer[buffer_size] = string_sub(input, i, i)
		end

		input_next_byte_pos = input_next_byte_pos + bytelen
		return buffer_size
	end

	local function decode(huffman_bitlen_counts, huffman_symbols, min_bitlen)
		local code = 0
		local first = 0
		local index = 0
		local count
		if min_bitlen > 0 then
			if cache_bitlen < 15 and input then
				local lshift_mask = _pow2[cache_bitlen]
				local byte1, byte2, byte3, byte4 = string_byte(input, input_next_byte_pos, input_next_byte_pos+3)
				cache = cache + ((byte1 or 0)+(byte2 or 0)*256
					+(byte3 or 0)*65536+(byte4 or 0)*16777216)*lshift_mask
				input_next_byte_pos = input_next_byte_pos + 4
				cache_bitlen = cache_bitlen + 32
			end

			local rshift_mask = _pow2[min_bitlen]
			cache_bitlen = cache_bitlen - min_bitlen
			code = cache % rshift_mask
			cache = (cache - code) / rshift_mask
			code = _reverse_bits_tbl[min_bitlen][code]

			count = huffman_bitlen_counts[min_bitlen]
			if code < count then
				return huffman_symbols[code]
			end
			index = count
			first = count * 2
			code = code * 2
		end

		for bitlen = min_bitlen+1, 15 do
			local bit
			bit = cache % 2
			cache = (cache - bit) / 2
			cache_bitlen = cache_bitlen - 1

			code = (bit==1) and (code + 1 - code % 2) or code
			count = huffman_bitlen_counts[bitlen] or 0
			local diff = code - first
			if diff < count then
				return huffman_symbols[index + diff]
			end
			index = index + count
			first = first + count
			first = first * 2
			code = code * 2
		end
		return -10
	end

	local function readerBitlenLeft()
		return (input_strlen - input_next_byte_pos + 1) * 8 + cache_bitlen
	end

	local function skipToByteBoundary()
		local skipped_bitlen = cache_bitlen%8
		local rshift_mask = _pow2[skipped_bitlen]
		cache_bitlen = cache_bitlen - skipped_bitlen
		cache = (cache - cache % rshift_mask) / rshift_mask
	end

	return readBits, readBytes, decode, readerBitlenLeft, skipToByteBoundary
end

local function createDecompressState(str, dictionary)
	local readBits, readBytes, decode, readerBitlenLeft, skipToByteBoundary = createReader(str)
	local state = {
		readBits = readBits,
		readBytes = readBytes,
		decode = decode,
		readerBitlenLeft = readerBitlenLeft,
		skipToByteBoundary = skipToByteBoundary,
		buffer_size = 0,
		buffer = {},
		result_buffer = {},
		dictionary = dictionary,
	}
	return state
end

local function decompressStoreBlock(state)
	local buffer, buffer_size, readBits, readBytes, readerBitlenLeft, skipToByteBoundary, result_buffer = state.buffer, state.buffer_size, state.readBits, state.readBytes, state.readerBitlenLeft, state.skipToByteBoundary, state.result_buffer

	skipToByteBoundary()
	local bytelen = readBits(16)
	if readerBitlenLeft() < 0 then
		return 2
	end
	local bytelenComp = readBits(16)
	if readerBitlenLeft() < 0 then
		return 2
	end

	if bytelen % 256 + bytelenComp % 256 ~= 255 then
		return -2 
	end
	if (bytelen-bytelen % 256)/256
		+ (bytelenComp-bytelenComp % 256)/256 ~= 255 then
		return -2 
	end

	buffer_size = readBytes(bytelen, buffer, buffer_size)
	if buffer_size < 0 then
		return 2
	end

	if buffer_size >= 65536 then
		result_buffer[#result_buffer+1] = table_concat(buffer, "", 1, 32768)
		for i=32769, buffer_size do
			buffer[i-32768] = buffer[i]
		end
		buffer_size = buffer_size - 32768
		buffer[buffer_size+1] = nil
	end
	state.buffer_size = buffer_size
	return 0
end

local function decodeUntilEndOfBlock(state, lcodes_huffman_bitlens, lcodes_huffman_symbols, lcodes_huffman_min_bitlen, dcodes_huffman_bitlens, dcodes_huffman_symbols, dcodes_huffman_min_bitlen)
	local buffer, buffer_size, readBits, decode, readerBitlenLeft, result_buffer = state.buffer, state.buffer_size, state.readBits, state.decode, state.readerBitlenLeft, state.result_buffer
	local dictionary = state.dictionary
	local dict_string_table
	local dict_strlen

	local buffer_end = 1
	if dictionary and not buffer[0] then
		dict_string_table = dictionary.string_table
		dict_strlen = dictionary.strlen
		buffer_end = -dict_strlen + 1
		for i=0, (-dict_strlen+1)<-257 and -257 or (-dict_strlen+1), -1 do buffer[i] = _byte_to_char[dict_string_table[dict_strlen+i]] end
	end

	repeat
		local symbol = decode(lcodes_huffman_bitlens, lcodes_huffman_symbols, lcodes_huffman_min_bitlen)
		if symbol < 0 or symbol > 285 then
			return -10
		elseif symbol < 256 then
			buffer_size = buffer_size + 1
			buffer[buffer_size] = _byte_to_char[symbol]
		elseif symbol > 256 then
			symbol = symbol - 256
			local bitlen = _literal_deflate_code_to_base_len[symbol]
			bitlen = (symbol >= 8) and (bitlen + readBits(_literal_deflate_code_to_extra_bitlen[symbol])) or bitlen
			symbol = decode(dcodes_huffman_bitlens, dcodes_huffman_symbols, dcodes_huffman_min_bitlen)
			if symbol < 0 or symbol > 29 then return -10 end
			local dist = _dist_deflate_code_to_base_dist[symbol]
			dist = (dist > 4) and (dist + readBits(_dist_deflate_code_to_extra_bitlen[symbol])) or dist

			local char_buffer_index = buffer_size-dist+1
			if char_buffer_index < buffer_end then return -11 end
			if char_buffer_index >= -257 then
				for _=1, bitlen do
					buffer_size = buffer_size + 1
					buffer[buffer_size] = buffer[char_buffer_index]
					char_buffer_index = char_buffer_index + 1
				end
			else
				char_buffer_index = dict_strlen + char_buffer_index
				for _=1, bitlen do
					buffer_size = buffer_size + 1
					buffer[buffer_size] =
						_byte_to_char[dict_string_table[char_buffer_index]]
					char_buffer_index = char_buffer_index + 1
				end
			end
		end

		if readerBitlenLeft() < 0 then return 2 end

		if buffer_size >= 65536 then
			result_buffer[#result_buffer+1] = table_concat(buffer, "", 1, 32768)
			for i=32769, buffer_size do buffer[i-32768] = buffer[i] end
			buffer_size = buffer_size - 32768
			buffer[buffer_size+1] = nil
		end
	until symbol == 256

	state.buffer_size = buffer_size

	return 0
end

local function decompressFixBlock(state)
	return decodeUntilEndOfBlock(state, _fix_block_literal_huffman_bitlen_count, _fix_block_literal_huffman_to_deflate_code, 7, _fix_block_dist_huffman_bitlen_count, _fix_block_dist_huffman_to_deflate_code, 5)
end

local function decompressDynamicBlock(state)
	local readBits, decode = state.readBits, state.decode
	local nlen = readBits(5) + 257
	local ndist = readBits(5) + 1
	local ncode = readBits(4) + 4
	if nlen > 286 or ndist > 30 then return -3 end

	local rle_codes_huffman_bitlens = {}

	for i = 1, ncode do rle_codes_huffman_bitlens[_rle_codes_huffman_bitlen_order[i]] = readBits(3) end

	local rle_codes_err, rle_codes_huffman_bitlen_counts, rle_codes_huffman_symbols, rle_codes_huffman_min_bitlen = getHuffmanForDecode(rle_codes_huffman_bitlens, 18, 7)
	if rle_codes_err ~= 0 then return -4 end

	local lcodes_huffman_bitlens, dcodes_huffman_bitlens = {}, {}
	local index = 0

	while index < nlen + ndist do
		local bitlen
		local symbol = decode(rle_codes_huffman_bitlen_counts, rle_codes_huffman_symbols, rle_codes_huffman_min_bitlen)

		if symbol < 0 then
			return symbol
		elseif symbol < 16 then
			if index < nlen then
				lcodes_huffman_bitlens[index] = symbol
			else
				dcodes_huffman_bitlens[index-nlen] = symbol
			end
			index = index + 1
		else
			bitlen = 0
			if symbol == 16 then
				if index == 0 then return -5
				end
				if index-1 < nlen then
					bitlen = lcodes_huffman_bitlens[index-1]
				else
					bitlen = dcodes_huffman_bitlens[index-nlen-1]
				end
				symbol = 3 + readBits(2)
			elseif symbol == 17 then 
				symbol = 3 + readBits(3)
			else 
				symbol = 11 + readBits(7)
			end
			if index + symbol > nlen + ndist then
				return -6
			end
			while symbol > 0 do
				symbol = symbol - 1
				if index < nlen then
					lcodes_huffman_bitlens[index] = bitlen
				else
					dcodes_huffman_bitlens[index-nlen] = bitlen
				end
				index = index + 1
			end
		end
	end

	if (lcodes_huffman_bitlens[256] or 0) == 0 then return -9 end
	local lcodes_err, lcodes_huffman_bitlen_counts, lcodes_huffman_symbols, lcodes_huffman_min_bitlen = getHuffmanForDecode(lcodes_huffman_bitlens, nlen-1, 15)
	if (lcodes_err ~=0 and (lcodes_err < 0 or nlen ~= (lcodes_huffman_bitlen_counts[0] or 0) +(lcodes_huffman_bitlen_counts[1] or 0))) then
		return -7
	end
	local dcodes_err, dcodes_huffman_bitlen_counts, dcodes_huffman_symbols, dcodes_huffman_min_bitlen = getHuffmanForDecode(dcodes_huffman_bitlens, ndist-1, 15)
	if (dcodes_err ~=0 and (dcodes_err < 0 or ndist ~= (dcodes_huffman_bitlen_counts[0] or 0) + (dcodes_huffman_bitlen_counts[1] or 0))) then
		return -8
	end

	return decodeUntilEndOfBlock(state, lcodes_huffman_bitlen_counts, lcodes_huffman_symbols, lcodes_huffman_min_bitlen, dcodes_huffman_bitlen_counts, dcodes_huffman_symbols, dcodes_huffman_min_bitlen)
end


local function inflate(str, dictionary)
	local state = createDecompressState(str, dictionary)
	local readBits = state.readBits

	local is_last_block
	while not is_last_block do
		is_last_block = (readBits(1) == 1)
		local block_type = readBits(2)
		local status
		if block_type == 0 then
			status = decompressStoreBlock(state)
		elseif block_type == 1 then
			status = decompressFixBlock(state)
		elseif block_type == 2 then
			status = decompressDynamicBlock(state)
		else
			return nil, -1
		end
		if status ~= 0 then
			return nil, status
		end
	end

	state.result_buffer[#state.result_buffer+1] = table_concat(state.buffer, "", 1, state.buffer_size)
	local result, status = table_concat(state.result_buffer)
	if not result then return nil, status end

	local bitlen_left = state.readerBitlenLeft()
	local bytelen_left = (bitlen_left - bitlen_left % 8) / 8
	return result, bytelen_left
end

return function(width, height, imagedata)
	imagedata = base64decode(imagedata);
	imagedata = inflate(imagedata);
	imagedata = base64decode(imagedata);
	imagedata = buffer_fromstring(imagedata);
		
	local image = {};
	local offset, rgb = 2, 1 / 255;
	for X = 1, width - 1 do
		for Y = 1, height - 1 do
			local R, G, B = buffer_readu8(imagedata, offset) * rgb, buffer_readu8(imagedata, offset + 1) * rgb, buffer_readu8(imagedata, offset + 2) * rgb;
			offset += 3
			table_insert(image, R); table_insert(image, G); table_insert(image, B); table_insert(image, 1);
			if offset % 50_000 == 0 then task.wait(); end;
		end;
	end;

	return image;
end
