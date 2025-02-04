module karcsnapshot; 

import het, het.bitmap, common.libueye, karcdetect, karcocr, karclogger; 

struct ProcessedSnapshot
{
	IDSCamera cam; 
	Bitmap bmp; 
	KarcSampleViewer logger; 
	
	uint encoderPos, triggerCounter; 
	
	//C3 only
	KarcOcr.Result ocrResult; 
	
	//C1, C2, C3
	DateTime key; 
	ivec2 lod0_size; 
	RGBA avgColor, thresholds; 
	ubyte[] lod0, lod3, lod6; 
	
	File getProcessedFile(int lod) const
	{
		if(!cam || !key) return File.init; 
		return encodeKarcPhotoFile(cam.index, key, lod); 
	} 
} 

private __gshared ProcessedSnapshot[3] _lastProcessedSnapshot; 

ref lastProcessedSnapshot(int i)
{
	enforce(i.inRange(1, 3)); 
	return _lastProcessedSnapshot[i-1]; 
} 


ref lastOcrResult()
{ lastProcessedSnapshot(3).ocrResult; } 


static processSnapshot(
	IDSCamera cam, Bitmap bmp, KarcSampleViewer logger, uint encoderPos,
	KarcDetectorSettings* settings, MainThreadJob onPaintJob, KarcOcr ocr,
	void delegate(int, RGBA) onSetThresholdMeasurements,
	void delegate(ref ProcessedSnapshot) onEarlyAcceptProcessedShanpsot
	/+
		Note: A complex background process.	
		First it detects (background),	
		then sends the results to the UI, 
		then it compresses (background)
	+/
)
{
	cam.stats.processing = true; scope(exit) cam.stats.processing = false; 
	cam.fProcessed = File.init; 
	
	auto res = ProcessedSnapshot(cam, bmp, logger); 
	
	try
	{
		convertOSExceptionsToNormalExceptions
		(
			{
				auto _間=init間; 
				//encoderPos, snapshotCounter
				res.encoderPos = encoderPos; 
				
				//C2 and C3 is on E3.
				res.triggerCounter = cam.triggerCounter;  
				
				enum invalidColor=RGBA(0xFFFF00FF); 
				
				Image2D!RGBA imLod0, imLod3, imLod6; 
				RGBA avgColor = invalidColor; 
				RGBA thresholds; 
				
				enum karcDetectEnabled = true; ((0x733FE420B7F).檢((update間(_間)))); 
				if(karcDetectEnabled && cam.name.among("C1", "C2"))
				{
					karcDetect_vulkan
					(
						cam.index.predSwitch(
							1, KARC_KERNEL_INSTANCE_CAM1,
							2, KARC_KERNEL_INSTANCE_CAM2,
						),
						bmp, settings,
						(
							b0,
							b3,
							b6,
							ac
						){
							//LOG("Karc Detection finished", now - t0); 
							imLod0 = b0.access!RGBA; 
							imLod3 = b3.access!RGBA; 
							imLod6 = b6.access!RGBA; 
							avgColor = ac; 
							thresholds = settings.thresholdsToRgb; 
							
							onSetThresholdMeasurements(cam.index, ac); 
						}
					); 
				}((0x9C2FE420B7F).檢((update間(_間)))); 
				
				enum ocrEnabled = true; 
				if(ocrEnabled && cam.name=="C3")
				{
					const t0 = now; 
					
					auto 	smp 	= new KarcOcr.Sample(bmp.file); 
					res.ocrResult = ocr.detect(smp, ocr.settings); 
					res.ocrResult.sample = smp; //Todo: dumb  (2 way linking is stupid.)
					smp.result = res.ocrResult; //Todo: dumber (this was needed to make it work)
					
					version(/+$DIDE_REGION Generate mipmaps+/all)
					{
						if(imLod0.empty) imLod0 = bmp.accessOrGet!RGBA; 
						if(imLod3.empty) imLod3 = imLod0.resize_nearest(max(imLod0.size/8, 1)); 
						if(imLod6.empty) imLod6 = imLod3.resize_nearest(max(imLod3.size/8, 1)); 
						if(avgColor == invalidColor)
						avgColor = ((imLod6.asArray.map!from_unorm.sum)/(imLod6.asArray.length)).to_unorm; 
					}
					LOG("Karc OCR finished", now-t0, res.ocrResult.detectedText); 
				}((0xD50FE420B7F).檢((update間(_間)))); 
				
				
				{
					res.key = bmp.modified; 
					res.lod0_size = imLod0.size;  
					res.avgColor = avgColor; 
					res.thresholds = thresholds; 
					
					version(/+$DIDE_REGION upload the images early into the bitmap cache+/all)
					{
						bitmaps.set(encodeKarcPhotoFile(cam.index, res.key, 0), res.key, imLod0); 
						bitmaps.set(encodeKarcPhotoFile(cam.index, res.key, 3), res.key, imLod3); 
						bitmaps.set(encodeKarcPhotoFile(cam.index, res.key, 6), res.key, imLod6); 
						
						cam.fProcessed = encodeKarcPhotoFile(cam.index, res.key, ((cam.index==3)?(0):(3))); 
					}((0xFD8FE420B7F).檢((update間(_間)))); 
					
					onPaintJob({ onEarlyAcceptProcessedShanpsot(res); }); ((0x1046FE420B7F).檢((update間(_間)))); 
					
					//Do the serializing
					static immutable fmt = (((常!(bool)(0)))?("webp quality=101") :("png")); 
					res.lod0 = imLod0.serialize(fmt); ((0x110DFE420B7F).檢((update間(_間)))); 
					res.lod3 = imLod3.serialize(fmt); ((0x1161FE420B7F).檢((update間(_間)))); 
					res.lod6 = imLod6.serialize(fmt); ((0x11B5FE420B7F).檢((update間(_間)))); 
					
					//When quality was 0:99, 3:98, 6:95, Lod3 was a lot brighter.
				}
			}
		); 
	}
	catch(Exception e)
	{ WARN(e.simpleMsg); }
	
	return res; 
} 
///Called after the image compression is done.
private void finalizeProcessedSnapshot(ref ProcessedSnapshot res)
{
	warnExceptions
	(
		{
			auto _間=init間; auto dataLogger = res.logger.S(res.cam.index); 
			auto entry = dataLogger[res.key].enforce(i"Invalid S key: $(res.key)".text); 
			with(entry)
			{
				lod0 = res.lod0,
				lod3 = res.lod3,
				lod6 = res.lod6; 
			}((0x1410FE420B7F).檢((update間(_間)))); 
			
			LOG(i"C$(res.cam.index) Images compressed.  Elapsed time: $(now-res.key)"); 
		}
	); 
} 

///Must be called from main thread. It writes the compressed images into the logger.
void finalizeProcessedSnapshots()
{
	foreach(ref res; futureFetch!processSnapshot)
	{ finalizeProcessedSnapshot(res); }
} 