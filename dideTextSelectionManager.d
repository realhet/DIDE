module didetextselectionmanager; 

import didebase; 
import didenode : visitNestedCodeColumns, visitNestedCodeNodes; 
import didedecl : Declaration; 
import didemodulemanager : ModuleManager; 


class TextSelectionManager
{
	mixin SmartChild!q{
		Container 	workspaceContainer,
		ModuleManager 	modules
	}; 
	
	struct MouseMappings
	{
		string 	main	= "LMB",
			scroll	= "MMB", //Todo: soft scroll/zoom, fast scroll
			menu	= "RMB",
			zoom	= "MW",
			zoomInHold	= "MB5",
			zoomOutHold	= "MB4",
			selectAdd	= "Alt",
			selectExtend	= "Shift",
			selectColumn	= "Shift+Alt",
			selectColumnAdd 	= "Ctrl+Shift+Alt"; 
	} 
	MouseMappings mouseMappings/+Todo: UI to edit this+/; 
	
	protected
	{
		TextSelection[] textSelections_internal; 
		bool mustValidateTextSelections; 
		size_t textSelectionsHash; 
		string[] extendSelectionStack; 
		
		@STORED int _dummy = 0; 
	} 
	
	@property
	{
		auto items()
		{
			validateTextSelectionsIfNeeded; 
			return textSelections_internal; 
		} 	auto textSelections()
		{ return items; } 
		void items()(TextSelection[] ts)
		{
			textSelections_internal = ts; 
			invalidateTextSelections; 
		} 	void textSelections()(TextSelection[] ts)
		{ items = ts; } 
		void items()(TextSelection ts)
		{ items = [ts]; } 	void textSelections()(TextSelection ts)
		{ items = ts; } 
	} 
	
	auto opIndex() => items; 
	auto opIndex(size_t i) => items.get(i); 
	auto length() => items.length; 
	auto empty() => items.empty; 
	
	auto primary()
	=> textSelections.filter!"a.primary".frontOr(textSelections.frontOr); 
	
	void clear() { items = []; } 
	
	
	
	version(/+$DIDE_REGION Validate+/all)
	{
		void invalidateTextSelections()
		{
			mustValidateTextSelections = true; 
			invalidateInternalSelections; 
		} 
		
		void validateTextSelectionsIfNeeded()
		{
			if(mustValidateTextSelections.chkClear)
			{ textSelections_internal = validate(textSelections_internal, workspaceContainer); }
		} 
	}
	
	
	string[] saveTextSelections()
	=> items.map!((a)=>(a.toReference.text)).array; 
	void restoreTextSelections(in string[] a)
	{ items = a.map!((a)=>(TextSelection(a, &modules.findModule))).array; } 
	
	
	void preserve(void delegate() fun)
	{
		//Todo: preserve module selections too
		const savedTextSelections = saveTextSelections; 
		scope(exit) restoreTextSelections(savedTextSelections); 
		if(fun) fun(); 
	} 
	
	string export_(TextSelection[] ts)
	=> ts.map!(a=>a.toReference.text).join(';'); 
	
	TextSelection[] import_(string s)
	=> s.splitter(';').map!(s=>s.TextSelectionReference(&modules.findModule).fromReference).array; 
	
	bool verify(string s)
	=> s == export_(validate(import_(s), workspaceContainer)); 
	
	bool extend(Flag!"selectAll" selectAll=No.selectAll)
	{
		const s0 = export_(textSelections); 
		textSelections = selectAll ? .extendAll(textSelections) : .extend(textSelections); 
		const s1 = export_(textSelections); 
		
		if(s0!="" && s1!="" && s0!=s1)
		{
			if(extendSelectionStack.length && extendSelectionStack.back==s0)
			extendSelectionStack ~= s1; 
			else
			extendSelectionStack = [s0, s1]; 
			return true; 
		}
		else
		return false; 
	} 
	
	bool shrink()
	{
		if(extendSelectionStack.length>=2)
		{
			const 	act = extendSelectionStack[$-1],
				prev = extendSelectionStack[$-2]; 
			if(act==export_(textSelections) && verify(prev))
			{
				textSelections = import_(prev); 
				extendSelectionStack = extendSelectionStack[0..$-1]; 
				return true; //success
			}
		}
		return false; 
	} 
	
	bool selectAll()
	=> extend(Yes.selectAll); 
	
	void select(R)(R arr)
	if(isInputRange!(R, Container.SearchResult))
	{
		//selectSearchResults ///////////////////////////
		//Todo: use this as a revalidator after the modules were changed under the search results.
		//Maybe verify the search results while drawing. Cache the last change or something.
		
		//T0; scope(exit) DT.LOG;
		
		//Todo: restrict to the current selection!
		
		//Todo: dont select text inside error messages!
		items = merge(arr.map!((a)=>(searchResultToTextSelection(a, workspaceContainer))).filter!"a.valid".array); 
	} 
	
	void insertCursorAtStartOfEachLineSelected()
	{ items = .insertCursorAtStartOfEachLineSelected(items); } 
	
	void insertCursorAtEndOfEachLineSelected()
	{ items = .insertCursorAtEndOfEachLineSelected(items); } 
	
	void insertCursorVertically(int dir)
	{
		auto 	prev = items, 
			next = prev.dup; 
		
		foreach(ref ts; next)
		foreach(
			ref tc; ts.cursors
			/+
				Note: It is important to move the cursors separately here.
				Don't let TextSelection.move do cursor collapsing.
			+/
		)
		tc.move(ivec2(0, dir)); 
		
		items = merge(prev ~ next); 
	} 
	
	void insertCursorAbove()
	{ insertCursorVertically(-1); }  void insertCursorBelow()
	{ insertCursorVertically(1); } 
	
	
	Module[] modulesWithTextSelection()
	=> textSelections[].map!moduleOf.nonNulls.uniq.array; 
	
	/+
		+Selects all the CodeColumns under the cursors. 
		If there is none, selects all the modules' content CodeColumns.
	+/
	CodeColumn[] selectedOuterColumns()
	{
		CodeColumn[] cols; 
		
		foreach(c; textSelections.map!"a.codeColumn")
		if(!cols.canFind(c)) cols ~= c; 
		if(cols.empty)
		foreach(c; modules.selectedModules.map!"a.content")
		cols ~= c; 
		
		return cols; 
	} 
	
	void visitSelectedNestedCodeColumns(void delegate(CodeColumn) fun)
	{
		foreach_reverse(col; selectedOuterColumns)
		visitNestedCodeColumns(col, fun); 
	} 
	
	void visitSelectedNestedCodeNodes(void delegate(CodeNode) fun)
	{
		foreach_reverse(col; selectedOuterColumns)
		visitNestedCodeNodes(col, fun); 
	} 
	
	void visitSelectedNestedDeclarations(void delegate(Declaration) fun)
	{ visitSelectedNestedCodeNodes((node){ if(auto decl = cast(Declaration) node) fun(decl); }); } 
	
	version(/+$DIDE_REGION Mouse ops on textSelections+/all)
	{
		struct SELECTIONS; 
		@SELECTIONS
		{
			//Note: these cursors MUST BE validated!!!!!
			TextCursor cursorAtMouse, cursorToExtend; 
			TextSelection	selectionAtMouse; 
			TextSelection[] 	selectionsWhenMouseWasPressed; 
		} 
		
		bool 	mouseScrolling,
			wordSelecting,
			cursorToExtend_primary; 
		
		Nullable!vec2 	scrollInRequest; 
		
		version(/+$DIDE_REGION validation of textSelections+/all)
		{
			bool mustValidateInternalSelections; 
			
			
			public void invalidateInternalSelections()
			{ mustValidateInternalSelections = true; } 
			
			void validateInternalSelections()
			{
				if(mustValidateInternalSelections.chkClear)
				{
					//validate all the cursors market with @SELECTIONS UDA
					static foreach(f; FieldNamesWithUDA!(typeof(this), SELECTIONS, false))
					mixin(format!"%s = validate(%s, workspaceContainer);"(f, f)); 
				}
			} 
		}
		
		version(/+$DIDE_REGION preprocess mouse input+/all)
		{
			private
			{
				bool 	opSelectColumn,
					opSelectColumnAdd,
					opSelectAdd,
					opSelectExtend; 
				
				DateTime lastMainMousePressTime; 
				ClickDetector cdMainMouseButton; 
				float mouseTravelDistance = 0; 
				bool doubleClick; 
				
				void updateInputs(in MouseMappings mouseMappings)
				{
					//detectMouseTravel
					if(inputs[mouseMappings.main].down)
					{
						//Todo: copy/paste
						mouseTravelDistance += abs(inputs.MX.delta) + abs(inputs.MY.delta); 
					}
					else
					{ mouseTravelDistance = 0; }
					
					cdMainMouseButton.update(inputs[mouseMappings.main].down); 
					doubleClick = cdMainMouseButton.doubleClicked; 
					
					//check if a keycombo modifier with the main mouse button isactive
					bool _kc(string sh) { return KeyCombo([sh, mouseMappings.main].join("+")).active; } 
					opSelectColumn = _kc(mouseMappings.selectColumn	); 
					opSelectColumnAdd = _kc(mouseMappings.selectColumnAdd	); 
					opSelectAdd = _kc(mouseMappings.selectAdd	); 
					opSelectExtend = _kc(mouseMappings.selectExtend	); 
				} 
			} 
		}
		
		
		
		bool update(
			View2D view, //input: mouse position,  output: zoom/scroll.
			TextCursor delegate(vec2) createCursorAt,
			bool mainIsForeground, float wheelSpeed
		)
		{
			//Todo: make textSelection functional, not a ref
			//Opt: only call this when the workspace changed (remove module, cut, paste)
			
			validateInternalSelections; 
			cursorAtMouse = createCursorAt(view.mousePos.vec2); 
			
			updateInputs(mouseMappings); 
			scrollInRequest.nullify; 
			if(doubleClick) { wordSelecting = true; }
			
			void initiateMouseOperations()
			{
				if(auto dw = inputs[mouseMappings.zoom].delta) view.zoomAroundMouse(dw*wheelSpeed); 
				if(inputs[mouseMappings.zoomInHold].down) view.zoomAroundMouse(.125); 
				if(inputs[mouseMappings.zoomOutHold].down) view.zoom/+AroundMouse+/(-.125); 
				
				if(inputs[mouseMappings.scroll].pressed) mouseScrolling = true; 
				
				if(inputs[mouseMappings.main].pressed)
				{
					if(textSelections.hitTest(view.mousePos.vec2))
					{
						//Todo: start dragging the selection contents and paste on mouse button release
					}
					else if(cursorAtMouse.valid)
					{
						//start selecting with mouse
						selectionsWhenMouseWasPressed = textSelections.dup; 
						
						if(textSelections.empty)
						{
							if(doubleClick)
							{
								selectionAtMouse = TextSelection(cursorAtMouse, false); 
								wordSelecting = false; 
							}else {
								//single click goes to module selection
							}
						}
						else
						{
							//extension cursor is the nearest selection.cursors[0]
							if(!doubleClick)
							{
								auto selectionToExtend = 	selectionsWhenMouseWasPressed
									.filter!(a => a.codeColumn is cursorAtMouse.codeColumn)
									.minElement!(a => distance(a, cursorAtMouse))(TextSelection.init); 
								
								cursorToExtend = selectionToExtend.cursors[0]; 
								cursorToExtend_primary = selectionToExtend.primary; 
							}
							
							if(!cursorToExtend.valid)
							{
								cursorToExtend = cursorAtMouse; //defaults extension pos is mouse press pos.
								cursorToExtend_primary = false; 
							}
							
							selectionAtMouse = TextSelection(cursorAtMouse, false); 
						}
					}
				}
			} 
			
			void updateMouseScrolling() //(middle button panning)
			{
				if(mouseScrolling)
				{
					if(!inputs[mouseMappings.scroll])
					mouseScrolling = false; 
					else if(const delta = inputs.mouseDelta)
					view.scroll(delta); 
				}
			} 
			
			void restrictDraggedMousePos()
			{
				//restrict dragged mousePos to the bounds of the current codeColumn
				if(selectionAtMouse.valid && mainIsForeground && inputs[mouseMappings.main])
				{
					auto bnd = worldInnerBounds(selectionAtMouse.codeColumn); 
					bnd.high = nextDown(bnd.high); //make sure it's inside
					
					const restrictedMousePos = opSelectColumn || opSelectColumnAdd 	? restrictPos_normal(view.mousePos.vec2, bnd) //normal clamping for columnSelect
						: restrictPos_editor(view.mousePos.vec2, bnd) /+text editor clamping for normal select+/; 
					
					auto restrictedCursorAtMouse = createCursorAt(restrictedMousePos); 
					
					if(restrictedCursorAtMouse.valid && restrictedCursorAtMouse.codeColumn==selectionAtMouse.codeColumn)
					selectionAtMouse.cursors[1] = restrictedCursorAtMouse; 
					
					if(mouseTravelDistance>4)
					{
						scrollInRequest = restrictPos_normal(view.mousePos.vec2, bnd); 
						//always normal clipping for mouse focus point
					}
				}
			} 
			
			void handleReleasedSelectionButton()
			{
				//resets mouse selection when the button is released
				if(selectionAtMouse.valid && !inputs[mouseMappings.main])
				{
					selectionAtMouse = TextSelection.init; 
					selectionsWhenMouseWasPressed = []; 
					wordSelecting = false; 
				}
			} 
			void combineFinalSelection()
			{
				//combine previous selection with the current mouse selection
				
				if(!selectionAtMouse.valid) return; //nothing to do with an empty selection
				
				//Todo: for additive operations, only the selections on the most recent
				
				auto applyWordSelect(TextSelection s) { return wordSelecting ? s.extendToWordsOrSpaces : s; } 
				auto applyWordSelectArr(TextSelection[] s) { return wordSelecting ? s.map!(a => a.extendToWordsOrSpaces).array : s; } 
				
				TextSelection[] ts; //the new text selection
				
				if(opSelectColumn || opSelectColumnAdd)
				{
					auto getPrimaryCursor()
					{
						auto a = selectionsWhenMouseWasPressed.filter!"a.primary"; 
						if(!a.empty) return a.front.cursors[0]; 
						return cursorToExtend; 
					} 
					
					//Column select
					auto 	c0	= opSelectColumnAdd 	? selectionAtMouse.cursors[0] 
								: getPrimaryCursor,  //Bug: what if primary cursor is on another module
						c1	= selectionAtMouse.cursors[1]; 
					
					const 	downward 	= c0.pos.y<c1.pos.y,
						dir	= downward ? 1 : -1,
						count	= abs(c0.pos.y-c1.pos.y)+1; 
					
					auto 	a0 = iota(count).map!((i){ auto res = c0; c0.move(ivec2(0,  dir)); return res; }).array,
						a1 = iota(count).map!((i){ auto res = c1; c1.move(ivec2(0, -dir)); return res; }).array; 
					
					if(downward) a1 = a1.retro.array; else a0 = a0.retro.array; 
					
					ts = iota(count).map!(i => TextSelection(a0[i], a1[i], false)).array; 
					assert(ts.isSorted); 
					
					if(opSelectColumn)
					{
						//the first selection created is at the mosue, it must be the primary
						(downward ? ts.front : ts.back).primary = true; 
					}
					
					//if there are any nonZeroLength selections, remove all zeroLength carets
					if(ts.any!"!a.isZeroLength")
					ts = ts.remove!"a.isZeroLength"; 
					
					//if all are carets, remove those at line ends
					if(ts.all!"a.isZeroLength" && !ts.all!"a.isAtLineStart" && !ts.all!"a.isAtLineEnd")
					{
						/+
							Todo: Shift+Alt+LMB multicursor bug
							01,
							
							02,
							03
							Can't put 3 cursors after the numbers, only 2.
						+/
						ts = ts.remove!"a.isAtLineEnd"; 
					}
					
					ts = applyWordSelectArr(ts); 
					
					if(
						opSelectColumnAdd//Ctrl+Alt+Shift = add column selection
					)
					ts = merge(selectionsWhenMouseWasPressed ~ ts); 
					
				}
				else if(opSelectAdd || opSelectExtend)
				{
					auto actSelection = applyWordSelect(
						opSelectAdd 	? selectionAtMouse
							: TextSelection(
							cursorToExtend, 
							selectionAtMouse.caret, 
							cursorToExtend_primary
						)
							//Bug: what if primary cursor to extend is on another module
					); 
					//remove touched existing selections first.
					auto baseSelections = selectionsWhenMouseWasPressed.remove!(a => touches(a, actSelection)); 
					ts = merge(baseSelections ~ actSelection); 
				}
				else
				{
					auto s = applyWordSelect(selectionAtMouse); 
					ts = [s]; 
				}
				
				//Todo: some selection operations may need 'overlaps' instead of 'touches'. Overlap only touch when on operand is a zeroLength selection.
				//automatically mark primary for single selections
				if(ts.length==1)
				ts[0].primary = true; 
				
				textSelections = ts; 
			} 
			
			//selection bussiness logic
			if(!im.wantMouse && mainIsForeground && view.isMouseInside) initiateMouseOperations; 
			updateMouseScrolling; 
			restrictDraggedMousePos; 
			handleReleasedSelectionButton; 
			combineFinalSelection; 
			
			const changed = textSelectionsHash.chkSet(textSelections.hashOf); 
			return changed; 
		} 
	}
	void UI_structureLevel()
	{
		with(im) {
			BtnRow(
				{
					auto mods = modules.selectedModules; 
					if(mods.empty) mods = modulesWithTextSelection; 
					
					static foreach(lvl; EnumMembers!StructureLevel)
					{
						{
							const capt = lvl.text[0..1].capitalize; 
							if(
								Btn(
									{
										style.bold = mods.any!((m)=>(m.structureLevel==lvl)); 
										Text(capt); 
									}, 
									genericId(capt), 
									selected(modules.desiredStructureLevel==lvl), 
									{ width = fh/4; },
									hint("Select desired StructureLevel.\n(Ctrl = reload and apply)")
								)
							)
							{
								modules.desiredStructureLevel = lvl; 
								
								if(
									inputs.Ctrl.down//apply
								)
								preserve
								(
									{
										Module[] cantReload; 
										foreach(m; mods)
										if(m.structureLevel != modules.desiredStructureLevel)
										{
											if(m.changed)	{ cantReload ~= m; }
											else	{ m.reload(modules.desiredStructureLevel); }
										}
										
										if(!cantReload.empty)
										{
											beep; 
											WARN(
												"Unable to reload modules because they has unsaved changes. ", 
												cantReload.map!"a.file.name"
											); 
										}
									}
								); 
							}
						}
					}
				}
			); 
		}
	} 
	
	void draw(Drawing dr, View2D view)
	{
		version(/+$DIDE_REGION+/all)
		{
			scope(exit) dr.alpha = 1; 
			
			const 	near	= lod.zoomFactor.smoothstep(0.02, 0.1),
				clSelected	= mix(
				mix(RGB(0x404040), clGray, near*.66f),
				mix(clWhite, clGray, near*.66f), blink
			),
				clCaret	= clSilver,
				clPrimaryCaret 	= clWhite,
				alpha	= mix(0.75f, .4f, near); 
			
			const cullBounds = view.subScreenBounds_anim; 
			
			dr.color = clSelected; 
			dr.alpha = alpha; 
			foreach(sel; textSelections[])
			if(!sel.isZeroLength)
			{
				auto col = sel.codeColumn; 
				const 	colInnerPos	= worldInnerPos(col), //Opt: group selections by codeColumn.
					colInnerBounds 	= bounds2(colInnerPos, colInnerPos+col.innerSize); 
				if(cullBounds.overlaps(colInnerBounds))
				{
					const localCullBounds = cullBounds - colInnerPos; 
					auto 	st	= sel.start,
						en 	= sel.end; 
					
					const 	pages = col.getPageRowRanges,
						singlePage = pages.length==1; 
					
					foreach(y; st.pos.y..en.pos.y+1)
					{
						//Todo: this loop is in the copy routine as well. Must refactor and reuse
						auto row = col.rows[y]; 
						const rowCellCount = row.cellCount; 
						
						//culling
						if(row.outerBottom < localCullBounds.top) continue;  //Opt: trisect
						if(singlePage)
						{ if(row.outerTop > localCullBounds.bottom) break; }
						else
						{
							if(row.outerTop > localCullBounds.bottom) continue; //next page can follow
							if(row.outerLeft > localCullBounds.right) break; 
						}
						
						const 	isFirstRow 	= y==st.pos.y,
							isLastRow	= y==en.pos.y; 
						const 	x0 	= isFirstRow ? st.pos.x : 0,
							x1	= isLastRow ? en.pos.x : rowCellCount+1; 
						const 	rowInnerPos 	= colInnerPos + row.innerPos; 
						
						dr.translate(rowInnerPos); scope(exit) dr.pop; 
						
						if(lod.level<=1)
						{
							foreach(x; x0..x1)
							{
								
								void fade(bounds2 bnd)
								{
									dr.color = clSelected; 
									dr.alpha = alpha; 
									
									enum gap = .5f; 
									if(isFirstRow)
									{
										bnd.top += gap; 
										if(x==x0) bnd.left += gap; 
									}
									if(isLastRow)
									{
										bnd.bottom -= gap; 
										if(x==x1-1) bnd.right -= gap; 
									}
									dr.fillRect(bnd); 
								} 
								
								assert(x.inRange(0, rowCellCount), "out of range"); 
								if(x<rowCellCount)
								{
									/+
										Todo: make the nice version: the font will be NOT blended to gray, 
										but it hides the markerLayers completely. Should make a 
										text drawer that uses alpha on the background and leaves 
										the font color as is.
									+/
									/+
										if(auto g = row.glyphs[x]){
											const old = tuple(g.bkColor, g.fontColor);
											g.bkColor = mix(g.bkColor, clSelected, alpha);// g.fontColor = clBlack;
											dr.alpha = 1;
											g.draw(dr);
											g.bkColor = old[0]; g.fontColor = old[1];
										}else
									+/
									{ fade(row.subCells[x].outerBounds); }
								}
								else
								{
									//newLine
									auto g = newLineGlyph; 
									const originalSize = g.outerSize; 
									const mustShrink = g.outerHeight>row.outerHeight+.125f; 
									if(mustShrink) g.outerSize = originalSize * (row.outerHeight / g.outerHeight); 
									scope(exit) if(mustShrink) g.outerSize = originalSize; 
									
									g.bkColor = row.bkColor;  g.fontColor = clGray; 
									dr.alpha = 1; 
									g.outerPos = row.newLinePos; 
									g.draw(dr); 
									
									fade(g.outerBounds); 
								}
							}
							
						}
						else
						{
							if(!isFirstRow && !isLastRow)
							{
								if(row.cellCount)
								dr.fillRect(bounds2(0, 0, row.subCells.back.outerRight, row.innerHeight)); 
							}
							else
							{
								dr.fillRect(
									bounds2(
										row.localCaretPos(x0).pos.x, 0, 
										row.localCaretPos(x1).pos.x, row.innerHeight
									)
								); 
							}
						}
					}
					
				}
			}
		}version(/+$DIDE_REGION+/all)
		{
			//caret trail
			static if(AnimatedCursors)
			{
				if(textSelections.length <= MaxAnimatedCursors)
				{
					dr.alpha = blink/2; 
					dr.lineWidth = -1-(blink)*3; 
					dr.color = clCaret; 
					//Opt: culling
					//Opt: limit max munber of animated cursors
					foreach(s; textSelections[])
					{
						CaretPos[3] cp; 
						cp[0] = s.caret.worldPos; 
						cp[1..3] = cp[0]; 
						cp[2].pos += s.caret.animatedPos - s.caret.targetPos; 
						cp[2].height = s.caret.animatedHeight; 
						cp[1].pos = mix(cp[0].pos, cp[2].pos, .25f); 
						
						auto dir = cp[1].pos-cp[2].pos; 
						if(dir)
						{
							if(dir.normalize.x.abs<0.05f)
							{
								//vertical line
								vec2[2] p = [cp[1].pos, cp[2].pos]; 
								if(p[0].y<p[1].y) p[1].y += cp[2].height; 
								else p[0].y += cp[1].height; 
								dr.line(p[0], p[1]); 
							}
							else
							{
								//horizontal bar
								vec2[4] p; 
								p[0] = cp[1].pos; 
								p[1] = cp[1].pos + vec2(0, cp[1].height); 
								p[2] = cp[2].pos + vec2(0, cp[2].height); 
								p[3] = cp[2].pos; 
								
								if(p[0].x<p[3].x)
								{
									dr.fillTriangle(p[0], p[1], p[3]); 
									dr.fillTriangle(p[1], p[2], p[3]); 
								}
								else
								{
									dr.fillTriangle(p[3], p[2], p[0]); 
									dr.fillTriangle(p[2], p[1], p[0]); 
								}
							}
						}
					}
				}
			}
			
			
			{
				const clamper = RectClamperF(view, 7*blink+2); 
				
				auto getCaretWorldPos(TextSelection ts)
				{
					CaretPos res = ts.caret.worldPos; 
					
					if(!clamper.overlaps(res.bounds))
					{
						res.pos = clamper.clamp(res.center); 
						res.height = lod.pixelSize; 
					}
					
					return res; 
				} 
				
				auto carets = textSelections[].map!getCaretWorldPos.array; 
				
				void drawCarets(RGB c, float shadow=0)
				{
					dr.alpha = blink; 
					dr.lineWidth = -1-(blink)*3 -shadow; 
					dr.color = c; 
					foreach(cwp; carets) cwp.draw(dr); 
				} 
				
				drawCarets(clBlack, 3); 	//shadow
				drawCarets(clCaret); 	//inner
				
				//primary
				if(auto ts = primary)
				{
					dr.color = clPrimaryCaret; 
					getCaretWorldPos(ts).draw(dr); 
				}
			}
		}
	} 
	
	
} 