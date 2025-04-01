module didetextselectionmanager; 

import het.ui, didebase; 
import didemodule : Module; 
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
	
	void preserve(void delegate() fun)
	{
		//Todo: preserve module selections too
		const savedTextSelections = items.map!((a)=>(a.toReference.text)).array; 
		scope(exit)
		{ items = savedTextSelections.map!((a)=>(TextSelection(a, &modules.findModule))).array; }
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
		if(((0xBD25AE8A3C6).檢 (extendSelectionStack.length>=2)))
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
} 