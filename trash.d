
void convertBuildMessagesToSearchResults(ref BuildResult br)
{
	version(/+$DIDE_REGION+/none) {
		T0; 
		
		const outFile = File(`virtual:\__compilerOutput.d`); 
		
		outFile.write(br.sourceText); 
		
		const tAccessBuildMessages = DT;  //40 ms
		
		errorModule = new Module(null, "", StructureLevel.structured); 
		messageSourceTextByLocation.clear; 
		
		messageConnectionArrows.clear; 
		
		if(1)
		{
			//load all messages through a cache
			float y = 0; 
			errorModule.content.subCells = []; 
			foreach(msg; br.messages)
			{
				//hide messages of unselected markerLayers
				const messageIsVisible = markerLayerSettings[msg.type].visible; 
				
				if(!messageIsVisible) continue; 
				
				const src = msg.sourceText; 
				//extract all locations from the message.
				msg.allLocations.each!((in loc){ messageSourceTextByLocation[loc.text] = src; }); 
				
				buildMessageConnectionArrows(msg); 
				
				if(src !in messageUICache)
				{
					//Todo: use CodeColumn here!
					auto tempModule = new Module(null, msg.sourceText, StructureLevel.structured); 
					try
					{
						auto msgCol = new CodeColumn(null, msg.sourceText, TextFormat.managed_block); 
						auto msgRow = msgCol.rows.frontOrNull.enforce("Can't get builMsgRow."); 
						msgRow.measure; 
						messageUICache[src] = msgRow; 
						
						version(none)
						{
							version(/+$DIDE_REGION Inject the error message into the nearest surrounding CodeNode+/all)
							{
								{
									auto msgNode = msgRow.singleNodeOrNull.enforce("Unable to get single buildMessageNode."); 
									auto srs = codeLocationToSearchResults(msg.location); //Todo: slow
									CodeNode[] getNodePath(Container.SearchResult sr)
									{
										return sr.container.thisAndAllParents	.map!((a)=>((cast(CodeNode)(a))))
											.filter!((a)=>(a && a.canAcceptBuildMessages))
											.array.retro.array; 
									} 
									auto rootPath = srs.map!((a)=>(getNodePath(a))).fold!commonPrefix; 
									
									if(auto rootNode = rootPath.backOrNull)
									{
										rootNode.processBuildMessage(src, msgNode); 
										/+Todo: only add once, not always!+/
									}
								}
							}
						}
					}
					catch(Exception e)
					{ ERR("Can't build buildMessage: "~e.simpleMsg~"\nmsg: "~msg.sourceText~"\n"); }
				}
				
				auto msgRow = messageUICache[src]; 
				errorModule.content.subCells ~= msgRow; 
				
				with(msgRow)
				{
					setParent(errorModule.content); 
					outerPos = vec2(0, y); 
					y += outerHeight; 
				}
				
				//Todo: Why I need to spread this shit manually? Why errorModule.measure dont do this?
				//Bug: this cache is never emptied, it keeps growing.
			}
		}
		
		const tLoadErrorModule = DT; //110 ms
		
		errorModule.measure; 
		//Note: This calculates the height and width of the module. It fails to spread the rows vertically.
		
		const tMeasureErrorModule = DT; //0 ms (because of the messageUICache[])
		
		auto buildMessagesAsSearchResults(DMDMessage.Type type)
		{
			//Todo: opt
			//Todo: Build DIDE -> Some error messages has NO PATH.
			Container.SearchResult[] arr; 
			
			foreach(msgIdx, const msg; br.messages)
			if(msg.type==type)
			{
				auto sr = codeLocationToSearchResults(msg.location); 
				
				//Todo: Must fix this crap.  Many rows are is unable to find.  Especially the rows on the surfaces of the fucking Nodes.
				
				static if(0)
				if(sr.empty && msg.location.lineIdx>1)
				{
					auto loc2 = cast()msg.location; 
					loc2.lineIdx--; 
					sr = codeLocationToSearchResults(loc2, false); 
					//WARN("Trying previous line:", sr.empty ? EgaColor.ltRed("still a FAIL") : "success"); 
					/+
						Todo: "Unable to find line" error can reproduced when the problem is at the block closing '}'. 
						It is on the surface of the Node which has no updated lineIdx.
					+/
				}
				
				
				static if(0)
				if(sr.empty)
				{
					WARN("Unable to find line for BuildMessage:\n"~msg.text); 
					sr = codeLocationToSearchResults(msg.location, false); 
					if(sr.empty)
					{
						WARN("Skipping binary search:", sr.empty ? EgaColor.ltRed("still a FAIL") : "success"); 
						
						if(msg.location.lineIdx>1)
						{
							auto loc2 = cast()msg.location; 
							loc2.lineIdx--; 
							sr = codeLocationToSearchResults(loc2, false); 
							WARN("Trying previous line:", sr.empty ? EgaColor.ltRed("still a FAIL") : "success"); 
							/+
								Todo: "Unable to find line" error can reproduced when the problem is at the block closing '}'. 
								It is on the surface of the Node which has no updated lineIdx.
							+/
						}
					}
				}
				arr ~= sr; 
			}
			
			return arr; 
		} 
		
		/+
			Opt: it is a waste of time. this should be called only at buildStart, and at buildProgress, 
			module change, module move.
		+/
		//1.5ms, (45ms if not sameText but sameFile(!!!) is used in the linear findModule.)
		static if(0)
		foreach(t; EnumMembers!(DMDMessage.Type))
		if(!t.among(DMDMessage.Type.unknown, DMDMessage.Type.find, DMDMessage.Type.console))
		{ markerLayers[t].searchResults = buildMessagesAsSearchResults(t); }
		
		
		const tBuildSearchResults = DT; //60 ms
		
		//performance timing
		if(0)
		LOG(
			[tAccessBuildMessages, tLoadErrorModule, tMeasureErrorModule, tBuildSearchResults]
			.map!(a => a.value(milli(second))).format!"%(%.0f %)"
		); 
	}
} 

version(/+$DIDE_REGION+/none) {
	auto visitMarkerLayer(DMDMessage.Type type, void delegate(ref SearchResult sr) fun)
	{
		if(type==DMDMessage.Type.find)
		{ foreach(m; modules) foreach(ref sr; m.findSearchResults) fun(sr); }
		else
		{ foreach(m; modules) foreach(msg; m.messagesByType[type]) foreach(ref sr; msg.searchResults) fun(sr); }
	} 
}

void aaa()
{
	if(0)
	{
		//Note: this works only at the first dept level
		//Todo: deprecate this code
		auto a(T)(void delegate(T) f)
		{ if(auto x = cast(T)st.get(0).cell) { st.popFront; f(x); }} 
		a(
			(Module m)
			{
				res.file = m.file; 
				a(
					(CodeColumn col)
					{
						a(
							(CodeRow row)
							{
								if(auto lineIdx = col.subCells.countUntil(row)+1)
								{
									//Todo: parent.subcellindex/child.index
									res.lineIdx = lineIdx.to!int; 
									a(
										(Cell cell)
										{
											if(auto columnIdx = row.subCells.countUntil(cell)+1)
											{
												//Todo: parent.subcellindex/child.index
												res.columnIdx = columnIdx.to!int; 
											}
										}
									); 
								}
							}
						); 
					}
				); 
			}
		); 
	}
	else
	{}
} 

void aaaa()
{
	version(/+$DIDE_REGION+/none) {
		//error list
		if(workspace.showErrorList)
		with(im)
		Panel(
			PanelPosition.bottomClient,
			{
				margin = "0"; padding = "0"; //border = "1 normal gray";
				outerHeight = 200; 
				auto siz = innerSize; 
				Container
				(
					{
						outerSize = siz; 
						with(flags) {
							clipSubCells = true; 
							vScrollState = ScrollState.auto_; 
							hScrollState = ScrollState.auto_; 
						}
						
						if(auto mod = errorModule)
						{
							if(auto col = mod.content)
							{
								//total size placeholder
								Container({ outerPos = col.outerSize; outerSize = vec2(0); }); 
								
								flags.saveVisibleBounds = true; 
								if(auto visibleBounds = imstVisibleBounds(actId))
								{
									CodeRow[] visibleRows = col.rows.filter!(
										r => r.outerBounds.overlaps(visibleBounds)
										&& r.subCells.length
									).array; 
									//Opt: binary search
									
									actContainer.append(cast(Cell[])visibleRows); 
									//Note: append is important because it already has the spaceHolder Container.
								}
							}
							else
							WARN("Invalid errorList"); 
						}
					}
				); 
			}
		); 
	}
} 

version(/+$DIDE_REGION Probes+/all)
{
	deprecated("Use inspectors!")
	{
		version(none) { auto _testProbe() { return ((now).PR!()); } }
		const _testProbeId = format!"%s(%s)"(__FILE__.lc, __LINE__-1); 
		
		void _updateTestProbe()
		{ globalWatches.require(_testProbeId, Watch(_testProbeId)).update(now.text); } 
		
		void resetGlobalWatches()
		{
			foreach(ref w; globalWatches.byValue)
			{ w.value = ""; }
		} 
		
		deprecated struct Watch
		{
			string id; 
			
			string value; 
			
			vec2 relativePos; //vector from srcBounds.center to dstBounds.center
			
			private string _lastValue; 
			private Container _container; 
			
			void update(string value)
			{
				this.value = value; 
				
				if(_lastValue.chkSet(value)) _container = null; 
			} 
			
			void draw(Drawing dr, bounds2 srcBounds)
			{
				//this looks like a workspace with lots of modules on top of it.  
				//A second layer over the real modules.
				
				if(!_container)
				{
					with(im)
					{
						Column(
							{
								outerPos = pos; 
								flags.targetSurface = 0; 
								padding = "2"; 
								style.applySyntax(skConsole); bkColor = style.bkColor; 
								border = Border(1, BorderStyle.normal, style.fontColor); 
								Text(value); 
							}  
						); 
						_container = removeLastContainer; 
						_container.measure; 
					}
				}
				
				//Todo: no clipping yet
				if(auto c = _container)
				{
					enum shadowSize = 6, shadowAlpha=.33f; 
					
					/+if(!relativePos) +/relativePos = vec2(120, 0).rotate(QPS_local.value(second)); 
					c.outerPos = srcBounds.center + relativePos - c.outerSize/2; 
					
					const dstBounds = c.outerBounds; 
					
					//shadow
					if(shadowSize)
					{
						dr.alpha = shadowAlpha; 
						dr.color = clBlack; 
						dr.fillRect(c.outerBounds + shadowSize); 
						dr.alpha = 1; 
					}
					
					//line
					{
						dr.lineWidth = 1; 
						
						void doit(bool horiz, float x0, float y0, float x1, float y1)
						{
							void doit(bool shadow)
							{
								enum triangularThickness = 4; 
								
								const p0 = vec2(x0, y0); 
								const p1 = vec2(x1, y1) + (shadow ? shadowSize : 0); 
								
								if(triangularThickness)
								{
									const sh = (horiz ? vec2(0, 1) : vec2(1, 0)) * triangularThickness; 
									dr.fillTriangle(p0, p1+sh, p1-sh); 
									dr.fillTriangle(p0, p1-sh, p1+sh); 
								}
								else
								dr.line(p0, p1); 
							} 
							
							if(shadowSize)
							{
								dr.color = clBlack; 
								dr.alpha = shadowAlpha; 
								doit(true); 
								dr.alpha = 1; 
							}
							
							dr.color = clWhite; 
							doit(false); 
						} 
						
						const d = (normalize(dstBounds.center - srcBounds.center)); 
						if((magnitude(d.x))>(magnitude(d.y)))
						{
							if(d.x>0)	doit(1, srcBounds.x1, d.y.remap(-1, 1, srcBounds.top, srcBounds.bottom), dstBounds.x0, d.y.remap(1, -1, dstBounds.top, dstBounds.bottom)); 
							else	doit(1, srcBounds.x0, d.y.remap(-1, 1, srcBounds.top, srcBounds.bottom), dstBounds.x1, d.y.remap(1, -1, dstBounds.top, dstBounds.bottom)); 
						}
						else
						{
							if(d.y>0)	doit(0, d.x.remap(-1, 1, srcBounds.left, srcBounds.right), srcBounds.y1, d.x.remap(1, -1, dstBounds.left, dstBounds.right), dstBounds.y0); 
							else	doit(0, d.x.remap(-1, 1, srcBounds.left, srcBounds.right), srcBounds.y0, d.x.remap(1, -1, dstBounds.left, dstBounds.right), dstBounds.y1); 
						}
					}
					
					c.draw(dr); 
				}
			} 
		} 
		
		Watch[string] globalWatches; 
		
		struct Probe
		{
			string id; 
			NiceExpression node; 
			bounds2 bounds; //the bounds of the expression in world coods
		} 
		
		Probe[string] globalVisibleProbes; 
		
		string calcProbeId(NiceExpression node)
		{ return format!"%s(%s)"(node.moduleOf.file.fullName.lc, node.lineIdx.text); } 
		
		void addGlobalProbe(Drawing dr, NiceExpression node)
		{
			const id = calcProbeId(node); 
			globalVisibleProbes[id] = Probe(id, node, dr.inputTransform(node.innerBounds)); 
		} 
		
		void drawProbes(Drawing dr)
		{
			foreach(id, const probe; globalVisibleProbes)
			{
				//print("Visible:", probe); 
				/+
					dr.lineWidth = 4; 
					dr.color = clWhite; 
					dr.drawRect(probe.bounds); 
					dr.lineWidth = 1.333; 
					dr.color = clBlack; 
					dr.drawRect(probe.bounds); 
				+/
				
				dr.color = clYellow; dr.lineWidth = -5; dr.drawRect(probe.bounds); 
				dr.color = clBlack; dr.lineWidth = -2.5; dr.lineStyle = LineStyle.dash; dr.drawRect(probe.bounds); dr.lineStyle = LineStyle.normal; 
				dr.color = clYellow; dr.lineWidth = 5; dr.drawRect(probe.bounds); 
				dr.color = clBlack; dr.lineWidth = 2.5; dr.lineStyle = LineStyle.dash; dr.drawRect(probe.bounds); dr.lineStyle = LineStyle.normal; 
				
				if(auto watch = id in globalWatches)
				{
					//print("Found:", *watch); 
					watch.draw(dr, probe.bounds); 
				}
			}
		} 
	} 
}
//LOG("GCycle", garbageCycle);

//megaTextures[mtIdx].bin.dump;
//infoDump;

//auto allInfos = collectSubTexInfo2.filter!(i => i.info.texIdx==mtIdx); //on the current megatexture

//auto infosToUnload	= allInfos.filter!(i =>  i.canUnload).array;
//auto infosToSave	= allInfos.filter!(i => !i.canUnload).array;

//no need to wait pending because they are not allocated yet in the bins and update() only called from main thread, also it can start a GC
/+
	while(allInfos.map!(i => isPending(i.idx)).any){
		LOG("Waiting for pending textures...");
		sleep(10);
	}
+/

struct Textures {
	bool update()
	{
		auto _ = PROBE("Textures.Update"); 
		bool inv; 
		
		auto t0 = QPS; 
		
		enum UploadTextureMaxTime = 1.0*second/60; 
		size_t uploadedSize; 
		enum TextureFlushLimit = 8 << 20; 
		do
		{
			
			Bitmap bmp; 
			synchronized
			{
				if(synchLog)
				LOG("bmpQueue.popFirst(null) before"); 
				bmp = bmpQueue.popFirst(null); 
				if(synchLog)
				LOG("bmpQueue.popFirst(null) after"); 
			} 
			
			if(!bmp)
			break; 
			
			auto idx = bmp.tag; 
			
			pendingIndices.remove(idx); //not pending anymore so it can be reinvalidated
			
			if(idx in invalidateAgain)
			{
				//WARN("Delayed loaded bmp is in invalidateAgain.", idx);
				
				uploadSubTex(idx, bmp, true); 
				//this is here to finalize the allocation of the texture before the invalidation
				//Opt: disable the upload of this texture data
				
				invalidateAgain.remove(idx); 
				foreach(f, i; byFileName)
				if(i == idx)
				{
					 //Opt: slow linear search
					//WARN("Reinvalidating", f, idx);
					invalidate(f); 
					break; 
				}
				
			}
			else {
				uploadSubTex(idx, bmp); 
				
				//flush at every N megabytes so the transfer time of this particular upload can be measured and limited.
				uploadedSize += bmp.sizeBytes; 
				if(uploadedSize >= TextureFlushLimit)
				{
					uploadedSize -= TextureFlushLimit; 
					gl.flush; 
				}
			}
			
			inv = true; 
			
		}
		while(QPS-t0<UploadTextureMaxTime/*sec*/); 
		
		return inv; 
	} 
} 


	struct BitmapTransformation
{
	//BitmapTransformation (thumb) ////////////////////////////////////
	enum thumbKeyword = "?thumbOld"; 
	//?thumb32w		 specifies maximum width
	//?thumb32h		 specifies maximum height
	//?thumb32wh	  specifies maximum width and maximum height
	//?thumb32	  ditto
	//Todo: ?thumb32x24  different maxwidth and maxheight
	//Todo: keep aspect or not
	/+
		Todo: ?thumb=32w is not possible because processMarkupCommandLine() 
			uses the = pro parameters and it can't passed into this filename.
	+/
	//Todo: cache decoded full size image
	//Todo: turboJpeg small size extract
	
	File originalFile, transformedFile; 
	int thumbMaxSize; 
	bool maxWidthSpecified, maxHeightSpecified; 
	
	size_t sizeBytes; //used by bitmapQuery/detailed stats
	
	deprecated bool isThumb() const { return thumbMaxSize>0; } 
	
	bool isHistogram, isGrayHistogram; 
	//Todo: this is lame. This should be solved by registered plugins.
	
	bool isEffect; 
	
	this(File file)
	{
		transformedFile = file; 
		
		//try to decode thumbnail params
		string thumbDef, orig; 
		if(file.fullName.split2(thumbKeyword, orig, thumbDef, false/+must not strip!+/))
		{
			originalFile = File(orig); 
			
			//get width/height posfixes
			while(1) {
				if(thumbDef.endsWith("w")) { maxWidthSpecified	= true; thumbDef.popBack; continue; }
				if(thumbDef.endsWith("h")) { maxHeightSpecified	= true; thumbDef.popBack; continue; }
				break; 
			}
			const maxAllSpecified = maxWidthSpecified == maxHeightSpecified; 
			if(maxAllSpecified)
			maxWidthSpecified = maxHeightSpecified = true; 
			
			ignoreExceptions({ thumbMaxSize = thumbDef.to!int; }); 
		}
		else if(file.fullName.canFind("?histogramOld"))	{
			originalFile = File(orig[0..orig.countUntil('?')]); 
			isHistogram = true; 
		}
		else if(file.fullName.canFind("?grayHistogramOld"))	{
			originalFile = File(orig[0..orig.countUntil('?')]); 
			isGrayHistogram = true; 
		}
		else {/+...+/}
	} 
	
	alias needTransform this; 
	bool needTransform()
	{ return isThumb|| isHistogram || isGrayHistogram || isEffect; } 
	
	Bitmap transform(Bitmap orig)
	{
		if(!orig || !orig.valid) return newErrorBitmap("Invalid source for BitmapTransform."); 
		
		sizeBytes = orig.sizeBytes; //used by bitmapQuery/detailed stats
		
		Bitmap doIt()
		{
			try
			{
				if(isThumb)
				{
					float minScale = 1; 
					if(maxWidthSpecified) minScale.minimize(float(thumbMaxSize) / orig.size.x); 
					if(maxHeightSpecified) minScale.minimize(float(thumbMaxSize) / orig.size.y); 
					
					if(minScale < 1) {
						ivec2 newSize = round(orig.size*minScale); 
						//print("THUMB", fn, thumbDef, "oldSize", orig.size, "newSize", newSize);
						return orig.resize_nearest(newSize); //Todo: mipmapped bilinear/trilinear
					}
				}
				else if(isHistogram)
				{
					auto img = orig.get!RGB; 
					int[3][256] histogram; 
					foreach(p; img.asArray) foreach(i; 0..3) histogram[p[i]][i]++; 
					int histogramMax = histogram[].map!(h => h[].max).array.max; 
					float sc = 255.0f/histogramMax; 
					return new Bitmap(image2D(256, 1, histogram[].map!(p => RGB(p[0]*sc, p[1]*sc, p[2]*sc)))); 
				}
				else if(isGrayHistogram)
				{
					auto img = orig.get!ubyte; 
					int[256] histogram; 
					foreach(p; img.asArray) histogram[p]++; 
					int histogramMax = histogram[].max; 
					float sc = 255.0f/histogramMax; 
					return new Bitmap(image2D(256, 1, histogram[].map!(p => cast(ubyte)((p*sc).iround)))); 
				}
				else if(isEffect)
				{ return orig.applyEffects(transformedFile); }
			}
			catch(Exception e) WARN(e.simpleMsg); 
			
			//Todo: handle errors
			return orig.dup; 
		} 
		
		//set filename and copy the modified time
		auto res = doIt; 
		res.file = transformedFile; 
		res.modified = orig.modified; 
		return res; 
	} 
	
} 
	class Texture
{
	//this holds all the info to access a subTexture
	private
	{
		int idx; 
		File file; 
		
		this(int idx)
		{
			//this is unnamed and empty
			this.idx = idx; 
		} 
	} 
	
	this(int idx, File file, bool delayed = false)
	{
		this(idx); 
		this.file = file; 
	} 
	
	override string toString() const
	{ return "Texture(#%d, %s)".format(idx, file); } 
} 
	deprecated(`Use bitmaps("name", bitmap)")`) class CustomTexture
{
	 //CustomTexture ///////////////////////////////
	const string name; 
	protected
	{
		Bitmap bmp; 
		bool mustUpload; 
	} 
	
	this(string name="")
	{ this.name = name.strip.length ? name : this.identityStr; } 
	
	void clear()
	{ bmp.destroy; mustUpload = false; } 
	void update()
	{ mustUpload = true; } 
	void update(Bitmap bmp)
	{ this.bmp = bmp; mustUpload = true; } 
	
	int texIdx()
	{
		if(bmp is null)
		return -1; //nothing to draw
		if(!textures.isCustomExists(name))
		mustUpload = true; //prepare for megaTexture GC
		Bitmap b = chkClear(mustUpload) ? bmp : null; 
		return textures.custom(name, b); 
	} 
	
	ivec2 size()const
	{ return bmp ? bmp.size : ivec2(0); } 
	
	auto getFile()
	{ return File(`custom:\`~name); } 
	auto getBmp()
	{ return bmp; } 
} 
	
	void overrideBuildResult(string output, bool clear=true)
{
	if(!ready) WARN("overrideBuildResult() while BuildSys is not ready."); 
	auto br = &buildResult; 
	if(clear) br.messages.clear; 
	br.insertSyntaxCheckOutput(output); 
	br.lastUpdateTime = now; //This trigger workspace.update()
} 
	/// Error collection ///////////////////////////////////
/+
	
	c:\d\libs\het\tokenizer.d(792,41): Deprecation: use `{ }` for an empty statement, not `;`
	c:\d\libs\quantities\internal\dimensions.d(101,5): Deprecation: Usage of the `body` keyword is deprecated. Use `do` instead.
	
	C:\D\projects\DIDE\dide2.d(383,22): Error:	constructor `dide2.Label.this(int height, bool bold, Vector!(float, 2) pos, string str, bool alignRight, float parentWidth = 0.0F)` is not callable using argument types `(int, bool, string, bool, const(float))`
	C:\D\projects\DIDE\dide2.d(383,22):	cannot pass argument `src.bigComments[k]` of type `string` to parameter `Vector!(float, 2) pos`
	
	C:\D\projects\DIDE\dide2.d(338,28): Error: undefined identifier `r`
	
	C:\D\projects\DIDE\dide2.d(324,7): Error: no property `height` for type `het.uibase.TextStyle`
		//todo: no property for type: missleading when the property name is correct but it's private or protected.
	
	C:\D\projects\DIDE\dide2.d(383,59): Error: found `src` when expecting `)`
	C:\D\projects\DIDE\dide2.d(383,104): Error: found `)` when expecting `;` following statement
	C:\D\projects\DIDE\dide2.d(383,104): Error: found `)` instead of statement
	
	C:\D\projects\DIDE\dide2.d(331,20): Error: cannot implicitly convert expression `isRegion` of type `const(uint)` to `bool`
	
	C:\D\testGetAssociatedIcon.d(29,15): Error: undefined identifier `DestroyIcon`
	
	C:\D\projects\DIDE\dide2.d(51,2): Error: `@identifier` or `@(ArgumentList)` expected, not `@{`
	
	C:\D\projects\DIDE\dide2.d(103,24): Error: found `cmd` when expecting `)`
	
	C:\D\projects\DIDE\dide2.d(103,28): Error: found `{` when expecting `;` following statement
	
	C:\D\projects\DIDE\dide2.d(104,5): Error: found `)` instead of statement
	
	C:\D\projects\DIDE\dide2.d(107,1): Error: unrecognized declaration
+/
deprecated("Use DMDMessageDecoder only!") struct DMDMessages
{
	alias messages this; 
	
	DMDMessage[] messages; 
	string[][File] pragmas; 
	
	//message filtering
	
	__gshared string[] messageFilters = ["Warning: C preprocessor directive "]; 
	//Todo: The filtered items should placed into a hidden category. Not the console output.
	
	//internal state
	private
	{
		DMDMessage[uint] messageMap; 
		public File actSourceFile; 
		DMDMessage parentMessage; 
		FileNameFixer fileNameFixer; 
	} 
	
	
	
	void dump()
	{
		void bar() { "-".replicate(80).print; } 
		messages.each!((m){ m.print; bar; }); 
		pragmas.keys.sort.each!((k){
			print(k.fullName, ": Pragma messages:"); 
			pragmas[k].each!((a){ print(a); }); bar; 
		}); 
	} 
	
	void createFileNameFixerIfNeeded()
	{ if(!fileNameFixer) fileNameFixer = new FileNameFixer; } 
	
	@property void defaultPath(Path path)
	{
		createFileNameFixerIfNeeded; 
		fileNameFixer.defaultPath = path; 
	} 
	
	string sourceText() const
	{ return messages.map!"a.sourceText".join("\n"); } 
	
	void processDMDOutput(string str)
	{ processDMDOutput(str.splitLines); } 
	
	private static bool keepMessage(in DMDMessage m)
	{
		foreach(f; messageFilters)
		if(joiner(only(DMDMessage.typePrefixes[m.type], m.content)).startsWith(f))
		return false; 
		
		return true; 
	} 
	
	void finalizePragmas(string extraText)
	{
		string[] arr; 
		foreach(f; pragmas.keys.sort)
		{
			auto list = pragmas[f]; 
			
			//remove empty lines
			while(list.length && list.front.empty) list.popFront; 
			while(list.length && list.back.empty) list.popBack; 
			
			auto s = list.join('\n'); 
			if(s.length) arr ~= s; 
		}
		
		foreach(i; 0..arr.length)
		foreach(j; 0..arr.length)
		if(i!=j && arr[i]!="" && arr[j]!="" && arr[j].canFind(arr[i]))
		arr[i] = ""; 
		
		if(extraText.length) arr = extraText ~ arr; 
		
		auto s = arr.filter!`a!=""`.join('\n'); 
		if(s!="")
		{
			auto m = new DMDMessage(CodeLocation.init, DMDMessage.Type.console, s); 
			messages = m ~ messages; 
		}
		
		pragmas.clear; 
	} 
	
	private enum rxDMDMessage = ctRegex!	`^((\w:\\)?[\w\\ \-.,]+.d)(-mixin-([0-9]+))?\(([0-9]+),([0-9]+)\): (.*)`
		/+1:fn 2:drive       3      4        5      6       7+/
		/+drive:\ is optional.+/; 
	
	static int decodeColumnMarker(string s)
	{
		return ((
			s.endsWith('^') &&
			(
				s.length==1 || 
				s[0..$-1].all!"a.among(' ', '\t')"
			)
		)?((cast(int)(s.length))):(0)); 
	} 
	static bool isColumnMarker(string s)
	{ return decodeColumnMarker(s)>0; } ; 
	
	
	static bool isDMDMessage(string s)
	{
		auto m = matchFirst(s, rxDMDMessage); 
		return !m.empty; 
	} 
	
	static bool isDMDMainMessage(string s)
	{
		auto m = matchFirst(s, rxDMDMessage); 
		if(!m.empty)
		{
			DMDMessage msg; 
			with(msg)
			{
				content = m[7]; detectType; 
				return type!=Type.unknown; 
			}
		}
		return false; 
	} 
	
	void processDMDOutput_partial(ref string[] lines, bool isFinal)
	{
		if(isFinal)
		{
			processDMDOutput(lines); 
			lines = []; 
		}
		else
		{
			auto prevLines = lines; 
			
			while(lines.length)
			{
				const s = lines.back; 
				
				//from here, break if it's a valid ending
				if(isColumnMarker(s)) { break; }
				else if(isDMDMessage(s))
				{
					const dqCnt = s.count('`'); 
					if(
						!dqCnt
						/+has no quotation inside+/
					) break; 
					if(
						(dqCnt%2==0) && 
						(s.count('"')==0) && 
						(s.count('\'')==0)
						/+
							has even quotation, 
							but no other strings
						+/
					) break; 
				}
				lines.popBack; 
			}
			
			processDMDOutput(lines); 
			lines = prevLines[lines.length..$]; 
		}
	} 
	
	void processDMDOutput(string[] lines)
	{
		if(lines.empty) return; 
		
		createFileNameFixerIfNeeded; 
		
		static File decodeFileMarker(string line, FileNameFixer fileNameFixer)
		{
			enum rx = ctRegex!`^(\w:\\[\w\\ \-.,]+.d): COMPILER OUTPUT:$`; 
			auto m = matchFirst(line, rx); 
			return m.empty ? File.init : fileNameFixer(m[1]); 
		} 
		
		static DMDMessage fetchDMDMessage(ref string[] lines, FileNameFixer fileNameFixer)
		{
			DMDMessage decodeDMDMessage(string s)
			{
				auto m = matchFirst(s, rxDMDMessage); 
				if(!m.empty)
				{
					return new DMDMessage
						(
						CodeLocation(
							fileNameFixer(m[1]).fullName, 
							m[5].to!int.ifThrown(0), 
							m[6].to!int.ifThrown(0), 
							m[4].to!int.ifThrown(0)
						), 
						m[7]
					); 
				}
				
				return null; 
			} 
			
			auto msg = decodeDMDMessage(lines.front); 
			if(msg)
			{
				int endIdx; 
				foreach(i; 1 .. lines.length.to!int)
				{
					if(decodeColumnMarker(lines[i])==msg.col)
					{ endIdx = i; break; }
					if(decodeDMDMessage(lines[i])) break; 
					if(decodeFileMarker(lines[i], fileNameFixer)) break; 
				}
				
				if(endIdx>=2 /+Note: endIdx==1 is invalid, that's  the cited line.+/)
				{
					lines.fetchFront; //first line of a multiline message
					foreach(i; 1..endIdx-1)
					if(lines.length)
					msg.content ~= "\n"~lines.fetchFront; 
					msg.lineSource = lines.fetchFront; 
					lines.fetchFront; //skip the marker line
				}
				else
				{
					lines.fetchFront; //slingle line message
				}
			}
			return msg; 
		} 
		
		while(lines.length)
		{
			if(auto msg = fetchDMDMessage(lines, fileNameFixer))
			{
				if(msg.isSupplemental && parentMessage)
				{
					auto idx = parentMessage.subMessages.map!"a.hash".countUntil(msg.hash); 
					if(idx>=0)
					{
						parentMessage = parentMessage.subMessages[idx]; 
						parentMessage.count++; 
					}
					else
					{
						parentMessage.subMessages ~= msg; /+new subMessage added+/
						parentMessage = msg; 
					}
				}
				else
				{
					if(msg.isSupplemental)
					WARN("No parent message for supplemental message:", msg); 
					
					if(keepMessage(msg))
					{
						const hash = msg.hash; 
						if(auto m = hash in messageMap)
						{
							(*m).count++; /+already exists+/
							parentMessage = *m; 
						}
						else
						{
							messages ~= msg; /+new top level message added+/
							messageMap[hash] = msg; 
							parentMessage = msg; 
						}
					}
				}
			}
			else if(auto f = decodeFileMarker(lines.front, fileNameFixer))
			{
				lines.popFront; 
				actSourceFile = f; 
			}
			else
			{ pragmas[actSourceFile] ~= lines.fetchFront; }
		}
		
	} 
} 
class BuildResult
{
	string unprocessedSourceTexts()
	{
		string[] res; 
		
		foreach(f; remainings.keys.sort)
		{
			if(f in remainings && remainings[f].length)
			{
				auto act = "/+Output:/+$DIDE_LOC "~f.fullName~"+/\n/+"; 
				foreach(a; remainings[f])
				act ~= safeDCommentBody(a)~'\n'; 
				act ~= "+/+/"; 
				
				res ~= act; 
			}
		}
		
		return res.join('\n'); 
	} 
	
	string sourceText()
	{ return only(unprocessedSourceTexts, messages.sourceText).join('\n'); } 
	
	void insertSyntaxCheckOutput(string output)
	{
		messages.processDMDOutput(output); 
		messages.finalizePragmas(""); 
	} 
} 