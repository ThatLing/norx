# NORX
GLua implementation of NORX

## Usage

```
local key = string.rep("a", 16)
local nonce = string.rep("b", 16)
local plainText = string.rep("c", 256)
local extra = string.rep("d", 128)

local cipherText = NORX.AEADEnc(key, nonce, extra, plainText, extra)

local decryptedText, err = NORX.AEADDec(key, nonce, extra, cipherText, extra)
if not decryptedText then
	error(err)
end

print(decryptedText == plainText)
```

Full specifications can be found [here](https://norx.io/data/norx.pdf).  
Based on [this](https://github.com/norx/norx/blob/master/norx3241/ref/norx.c) project.  
More information can be found [here](https://norx.io/).  
