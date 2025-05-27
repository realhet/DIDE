//@exe
//@debug

import het; 

const content = `$DIDE_EXTERNAL_COMPILATION_REQUEST: "5J9751C","\x01\x03glslc -O\x02\x01\x03\r\n\t\t\t\t\t#version 430\r\n\t\t\t\t\t@comp: \r\n\t\t\t\t\t\r\n\t\t\t\t\tlayout(local_size_x = \x04groupSize\x051024\x03) in; \r\n\t\t\t\t\t\r\n\t\t\t\t\tlayout(binding = 0) uniform UBO {\x04UBO_fields.replace(\"\\r\\n\", \" \").replace(\"\\n\", \" \")\x05 \t\tuint \tparam0,  \t\t\tparam1;  \t\x03}; \r\n\t\t\t\t\t\r\n\t\t\t\t\tlayout(std430, binding = 1) buffer BUF { uint values[]; }; \r\n\t\t\t\t\t\r\n\t\t\t\t\t/*\r\n\t\t\t\t\t\tint fuck = off; \r\n\t\t\t\t\t\tint fuck1 = off1; \r\n\t\t\t\t\t\tint fuck2 = off2; \r\n\t\t\t\t\t\tint fuck3 = off3; \r\n\t\t\t\t\t*/\r\n\t\t\t\t\t\r\n\t\t\t\t\tvoid main() {\r\n\t\t\t\t\t\tconst uint id = gl_GlobalInvocationID.x; \r\n\t\t\t\t\t\tvalues[id] = values[id] * param0 + param1 + 1333; \r\n\t\t\t\t\t} \r\n\t\t\t\t\t\r\n\t\t\t\t\t\r\n\t\t\t\t\x02"`; 
/+$DIDE_EXTERNAL_COMPILATION_REQUEST: "5J9751C","\x01\x03glslc -O\x02\x01\x03\r\n\t\t\t\t\t#version 430\r\n\t\t\t\t\t@comp: \r\n\t\t\t\t\t\r\n\t\t\t\t\tlayout(local_size_x = \x04groupSize\x051024\x03) in; \r\n\t\t\t\t\t\r\n\t\t\t\t\tlayout(binding = 0) uniform UBO {\x04UBO_fields.replace(\"\\r\\n\", \" \").replace(\"\\n\", \" \")\x05 \t\tuint \tparam0,  \t\t\tparam1;  \t\x03}; \r\n\t\t\t\t\t\r\n\t\t\t\t\tlayout(std430, binding = 1) buffer BUF { uint values[]; }; \r\n\t\t\t\t\t\r\n\t\t\t\t\t/*\r\n\t\t\t\t\t\tint fuck = off; \r\n\t\t\t\t\t\tint fuck1 = off1; \r\n\t\t\t\t\t\tint fuck2 = off2; \r\n\t\t\t\t\t\tint fuck3 = off3; \r\n\t\t\t\t\t*/\r\n\t\t\t\t\t\r\n\t\t\t\t\tvoid main() {\r\n\t\t\t\t\t\tconst uint id = gl_GlobalInvocationID.x; \r\n\t\t\t\t\t\tvalues[id] = values[id] * param0 + param1 + 1333; \r\n\t\t\t\t\t} \r\n\t\t\t\t\t\r\n\t\t\t\t\t\r\n\t\t\t\t\x02" /+$DIDE_LOC c:\D\helloVulkanCompute_highlevel.d(25,1)+/+/

void main() {
	console(
		{
			if(content.isWild("$DIDE_EXTERNAL_COMPILATION_REQUEST: *"))
			{
				try
				{
					//Try to decode the 3 string parameters
					string[] params; params.fromJson("["~wild[0]~"]"); 
					
					((0x830C763BD99).檢 (params)); 
					((0x857C763BD99).檢(params.length)); 
					
					if(params.length==3 /+old version+/)
					{
						const 	args 	= params[0], 
							incomingHash 	= params[1], 
							src 	= params[2]; 
						
						const calculatedHash = src.hashOf(args.hashOf).to!string(26); 
						enforce(
							incomingHash==calculatedHash, 
							i"Wrong hash $(incomingHash)!=$(calculatedHash)".text
						); 
						
						((0x9F6C763BD99).檢(args, "\n\n\n", src)); 
						goto done; 
					}
					
					if(params.length==2 /+new version+/)
					{
						const 	incomingHash 	= params[0], 
							srcParts 	= deserializeIES(params[1], ((0xAD0C763BD99).檢(incomingHash))); 
						enforce(srcParts.length==2, i"Invalid srcParts count: $(srcParts.length)".text); 
						const 	args 	= srcParts[0], 
							src 	= srcParts[1]; 
						((0xB98C763BD99).檢(args, "\n\n\n", src)); 
						goto done; 
					}
					
					enforce(0, i"Uknown paramCount: $(params.length)".text); 
				}
				catch(Exception e) {
					ERR(
						"Invalid External Code pragma message exception: "
						~e.simpleMsg~"\n"
						~content
					); 
				}
			}
			else if(false)
			{}
			
			done: 
		}
	); 
} 

//ldc2 testPragma.d --enable-color=0 > a.txt 2>&1