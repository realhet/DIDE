module dideeditor; 

import didebase; 
import didemodule : TextModification, TextModificationRecord, nearestDeclarationBlock; 
import didemodulemanager : ModuleManager; 
import didetextselectionmanager : TextSelectionManager; 
import didebuildmessagemanager : BuildMessageManager; 
import buildobjs : DMDMessage, decodeDMDMessages; 

class Editor
{
	mixin SmartChild!(
		q{
			ModuleManager modules,
			TextSelectionManager textSelections,
			IBuildServices buildServices,
			BuildMessageManager buildMessages
		},
		q{syntaxHighlightWorker = new SyntaxHighlightWorker; }
	); 
	
	struct ResyntaxEntry {
		CodeColumn what; 
		DateTime when; 
	} 
	ResyntaxEntry[] resyntaxQueue; 
	
	SyntaxHighlightWorker syntaxHighlightWorker; 
	
	
	@property bool isReadOnly()
	{
		return false; 
		//Note: it's making me angry if I can't modify while it's compiling.
		//Bug: deleting (it is not permitted, does nothing) from a readonly module loses its selections.
	} 
	
	
	version(/+$DIDE_REGION Permissions+/all)
	{
		protected
		{
			enum LogRequestPermissions = (常!(bool)(0)); 
			
			/+
				+ this value is incremented by every cut or paste batch operation.
						This controls undoOperation fuson, in order to preserve the order of
						multiselect cut and paste operations. (cursors are only vanid if they are in order.) 
			+/
			uint undoGroupId; 
			
			bool requestModifyPermission(CodeColumn col)
			{
				//Todo: constness
				assert(col); 
				if(isReadOnly) return false; 
				foreach(a; col.thisAndAllParents)
				{
					if(auto c = (cast(CodeColumn)(a))) if(c.containsBuildMessages) return false; 
					if(auto m = (cast(Module)(a))) return !m.isReadOnly; 
				}
				return false; 
			} 
			
			bool requestDeletePermission(TextSelection ts)
			{
				auto s = ts.sourceText; 
				/+
					this can throw if the structured contents are invalid. 
					If that goes into the undo, it would not be redo'd.
				+/
				
				auto res = requestModifyPermission(ts.codeColumn); 
				if(res)
				{
					static if(LogRequestPermissions)
					print(EgaColor.ltRed("DEL"), ts.toReference.text, s.quoted); 
					
					auto m = moduleOf(ts).enforce; 
					m.undoManager.justRemoved(undoGroupId, ts.toReference.text, s); 
				}
				return res; 
			} 
			
			static struct CollectedInsertRecord
			{
				int stage; 
				TextSelection textSelection; 
				string contents; 
				void reset()
				{ this = typeof(this).init; }                                                     
			} 
			CollectedInsertRecord collectedInsertRecord; 
			
			bool requestInsertPermission_prepare(TextSelection ts, string str)
			{
				auto res = requestModifyPermission(ts.codeColumn); 
				
				if(res) {
					auto m = moduleOf(ts).enforce; 
					static if(LogRequestPermissions)
					print(EgaColor.ltGreen("INS0"), ts.toReference, str.quoted); 
					with(collectedInsertRecord)
					{
						enforce(stage==0, "collectedInsertRecord.stage inconsistency 1"); 
						stage = 1; 
						textSelection = ts; 
						contents = str; 
					}
				}
				return res; 
			} 
			
			void requestInsertPermission_finish(TextSelection ts)
			{
				auto m = moduleOf(ts).enforce; 
				with(collectedInsertRecord)
				{
					enforce(stage==1, "collectedInsertRecord.stage inconsistency 2"); 
					static if(LogRequestPermissions)
					print(EgaColor.ltCyan("INS1"), ts.toReference); 
					
					textSelection.cursors[1] = ts.cursors[1]; 
					m.undoManager.justInserted(undoGroupId, textSelection.toReference.text, contents); 
					reset; 
				}
			} 
		} 
	}
	version(/+$DIDE_REGION Undo/Redo+/all)
	{
		void undoRedo_impl(string what)()
		{
			/+
				3 levels
					1. Save, SaveAll (ehhez csak egy olyan kell, hogy a legutolso save/load ota a user 
								 beleirt-e valamit.   Hierarhikus formaban lennenek a changed flag-ek, a soroknal 
								 meg lenne 2 extra: removedNextRow, removedPrevRow)
					2. Opcionalis Undo: ez csak 2 save kozott mukodhetne. Viszont a redo utani modositas
								 nem semmisitene meg az utana levo undokat, hanem csak becsatlakoztatna a graph-ba. 
								 Innentol nem idovonal van, hanem graph.
					3.	Opcionalis history: Egy kulon konyvtarba behany minden menteskori es betolteskori 
						allapotot. Ezt kesobb delta codinggal tomoriteni kell. 
			+/
			
			void executeUndoRedoRecord(in bool isUndo, in bool isInsert, in TextModificationRecord rec)
			{
				TextSelection ts; 
				bool decodeTs(bool reduceToStart)
				{
					string where = rec.where; 
					if(reduceToStart) where = where.reduceTextSelectionReferenceStringToStart; 
					ts = TextSelection(where, &modules.findModule); 
					bool res = ts.valid; 
					if(!res) WARN("Invalid ts: "~where); 
					return res; 
				} 
				
				const isCut = isUndo==isInsert; 
				
				if(decodeTs(!isCut))
				{
					if(isCut)
					cut_impl!true([ts]); 
					else
					paste_impl!true([ts], rec.what); 
					
					if(decodeTs(isCut))
					textSelections.items = ts; 
				}
			} 
			
			void executeUndoRedo(bool isUndo)(in TextModification tm)
			{
				static if(isUndo) auto r = tm.modifications.retro; else auto r = tm.modifications; 
				r.each!(m => executeUndoRedoRecord(isUndo, tm.isInsert, m)); 
			} 
			
			void execute_undo(in TextModification tm)
			{ executeUndoRedo!true (tm); } void execute_redo(in TextModification tm)
			{ executeUndoRedo!false(tm); } 
			
			void execute_reload(string where, string what)
			{
				if(auto m=modules.findModule(File(where)))
				{
					m.reload(modules.desiredStructureLevel, nullable(what)); 
					//selectAll
					textSelections.items = [m.content.allSelection(true)]; 
					//Todo: refactor codeColumn.allTextSelection(bool primary or not)
				}
				else
				assert(0, "execute_reload: module lost: "~where.quoted); 
				//Todo: somehow signal bact to the undo manager, if an undo operation is failed
			} 
			
			//Todo: select the latest undo/redo operation if there are more than 
			//one modules selected. If no modules selected: select from all of them.
			if(auto m = modules.primaryModule)
			{
				//Todo: undo should not remove textSelections on other modules.
				mixin(q{m.undoManager.$(&execute_$, &execute_reload); }.replace("$", what)); 
				textSelections.invalidateTextSelections; //because executeUndo don't call measure() so desiredX's are invalid.
			}
		} 
	}
	version(/+$DIDE_REGION Resyntax+/all)
	{
		class SyntaxHighlightWorker
		{
			//Todo: Make a BackgroundWorker pattern template
			static struct Job
			{
				DateTime changeId; //must be a globally unique id, also sorted by chronology
				CodeColumn col; //only one object allowed with the same referenceId
				
				bool valid; 
				bool opCast(b:bool)() const { return valid; } 
			} 
			
			private int destroyLevel; 
			private Job[] inputQueue, outputQueue; 
			
			void put(DateTime changeId, CodeColumn col)
			{
				synchronized(this)
					inputQueue = 	inputQueue.remove!(j => j.col is col) 
						~ Job(changeId, col); 
			} 
			
			Job getResult()
			{
				Job res; 
				synchronized(this)
					if(outputQueue.length)
						res = outputQueue.fetchFront; 
				return res; 
			} 
			
			private Job _workerGetJob()
			{
				Job res; 
				synchronized(this)
					if(inputQueue.length) {
					res = inputQueue.fetchBack; 
					res.valid = true; 
				} 
				return res; 
			} 
			
			private void _workerCompleteJob(Job job)
			{
				synchronized(this)
					outputQueue ~= job; 
			} 
			
			static private void worker(shared SyntaxHighlightWorker shw_)
			{
				auto shw = cast()shw_; 
				while(shw.destroyLevel==0)
				{
					if(auto job = shw._workerGetJob)
					{
						//actual work comes here
						shw._workerCompleteJob(job); 
					}
					else
					{
						//LOG("Worker Idling");
						sleep(10); 
					}
				}
				shw.destroyLevel = 2; 
				//LOG("Worker finished");
			} 
			
			this()
			{ spawn(&worker, cast(shared)this); } 
			
			~this()
			{
				destroyLevel = 1; 
				while(destroyLevel==1)
				{
					//LOG("Waiting for worker thread to finish");
					sleep(10); //Todo: it's slow... rewrite to message based
				}
			} 
		} version(/+$DIDE_REGION Resyntax+/all)
		{
			void needResyntax(CodeColumn col)
			{
				static DateTime uniqueTime; 
				uniqueTime.actualize; 
				scope(exit) col.lastResyntaxTime = uniqueTime; 
				
				const doItRightNow = (col.flags.columnIsTable && col.rowCount<1000); 
				if(doItRightNow)
				{
					/+
						Note: Immediate resyntax for smaller tables.
						It's annoying when the arrangement of the table cells are shifting.
					+/
					resyntaxNow(col); 
				}
				else
				{
					//Note: Delayed resyntax.  It's needed for large highlighted texts.
					if(
						//fast-update last item if possible
						resyntaxQueue.map!"a.what".backOrNull is col
					)
					{ resyntaxQueue.back.when = uniqueTime; }
					else
					{
						//remove if alreay exists
						resyntaxQueue = resyntaxQueue.remove!(e => e.what is col); 
						//add
						resyntaxQueue ~= ResyntaxEntry(col, uniqueTime); 
					}
				}
			} 
			
			void UI_ResyntaxQueue()
			{
				with(im) {
					foreach(e; resyntaxQueue)
					Row(
						{
							Row(e.when.text, { width = fh*9; }); 
							if(auto col = cast(CodeColumn)e.what)
							{
								auto tc = TextCursor(col, ivec2(0, 0)); 
								Row(tc.toReference.text); 
							}
						}
					); 
				}
			} 
			
			void resyntaxNow(CodeColumn col)
			{ col.resyntax; } 
			
			void resyntaxLater(CodeColumn col, DateTime changedId)
			{ syntaxHighlightWorker.put(changedId, col); } 
			
			/// returns true if any work done or queued
			bool updateResyntaxQueue()
			{
				if(auto job = syntaxHighlightWorker.getResult)
				{
					auto col = job.col; 
					if(col.getStructureLevel >= StructureLevel.highlighted)
					{
						static DateTime lastOutdatedResyncTime; 
						if(
							col.lastResyntaxTime==job.changeId || 
							now-lastOutdatedResyncTime > .25*second
						)
						{
							//mod.resyntax_src(job.sourceCode);
							resyntaxNow(col); 
							lastOutdatedResyncTime = now; 
						}
					}
				}
				
				if(resyntaxQueue.empty) return false; 
				
				//limit the frequency of slow sourceText() calls
				static DateTime lastResyntaxLaterTime; 
				if(now-lastResyntaxLaterTime < .25*second) return false; 
				lastResyntaxLaterTime = now; 
				
				auto act = resyntaxQueue.fetchBack; 
				resyntaxLater(act.what, act.when); 
				return true; 
			} 
		}
	}
	version(/+$DIDE_REGION Cut Copy Paste+/all)
	{
		auto cut_impl(bool dontMeasure=false)(TextSelection[] textSelections, bool* returnSuccess=null)
		{
			undoGroupId++; 
			
			assert(textSelections.map!"a.valid".all && textSelections.isSorted); //Todo: merge check
			
			auto savedSelections = textSelections.map!"a.toReference".array; 
			
			if(returnSuccess !is null) *returnSuccess = true; //Todo: terrible way to
			
			void cutOne(TextSelection sel)
			{
				if(sel.isZeroLength) return; //nothing to do with empty selection
				if(auto col = sel.codeColumn)
				{
					const st = sel.start, en = sel.end; 
					
					foreach_reverse(y; st.pos.y..en.pos.y+1)
					{
						//Todo: this loop is in the draw routine as well. Must refactor and reuse
						if(auto row = col.getRow(y))
						{
							const rowCellCount = row.cellCount; 
							
							const 	isFirstRow	= y==st.pos.y,
								isLastRow	= y==en.pos.y,
								isMidRow	= !isFirstRow && !isLastRow; 
							if(isMidRow)
							{
								//delete whole row
								col.rows[y].setRemoved; 
								
								col.subCells = col.subCells.remove(y); 
								//Opt: do this in a one run batch operation.
							}
							else
							{
								//delete partial row
								const	x0 = isFirstRow	? st.pos.x	: 0,
									x1 = isLastRow 	? en.pos.x 	: rowCellCount+1; 
								
								foreach_reverse(x; x0..x1)
								{
									if(x>=0 && x<rowCellCount)
									{
										if(auto cntr = (cast(Container)(row.subCells[x]))) cntr.setRemoved; 
										
										row.subCells = row.subCells.remove(x); 
										//Opt: this is not so fast. It removes 1 by 1.
									}
									else if(x==rowCellCount)
									{
										//newLine
										if(auto nextRow = col.getRow(y+1))
										{
											foreach(ref ss; savedSelections)
											{
												//Opt: must not go througn all selection.
												//It could binary search the start position to iterate.
												ss.replaceLatestRow(nextRow, row); 
											}
											
											if(nextRow.subCells.length)
											{
												row.append(nextRow.subCells); 
												row.adoptSubCells; 
												//Note: it seems logical, but not help in tracking.
												//Always mark a cut with changedRemoved: row.setChangedCreated;
											}
											
											nextRow.subCells = []; 
											col.subCells = col.subCells.remove(y+1); 
										}
										else
										assert(0, "TextSelection out of range NL"); 
									}
									else
									assert(0, "TextSelection out of range X"); 
								}
								
								row.refreshTabIdx; 
								row.spreadElasticNeedMeasure; 
								row.setChangedRemoved; 
							}
						}
						else
						assert(0, "TextSelection out of range Y"); 
					}
					
					needResyntax(col); 
					col.edited = true; 
				}
				else
				assert(0, "TextSelection invalid CodeColumn"); 
			} 
			
			foreach_reverse(sel; textSelections)
			{
				if(!sel.isZeroLength)
				{
					if(requestDeletePermission(sel))
					{ cutOne(sel); }
					else
					{
						if(returnSuccess !is null) {
							//Todo: maybe it would be better to handle readOnlyness with an exception...
							*returnSuccess = false; 
						}
					}
				}
			}
			
			static if(!dontMeasure) modules.workspaceContainer.measure/+It's needed to calculate TextCursor.desiredX+/; 
			//Opt: measure is terribly slow when editing het.utils. 8ms in debug. SavedSelections are not required all the time.
			
			return savedSelections.map!"a.fromReference".filter!"a.valid".array; 
			
			/+Bug: must not fail when text selected inside error messages!+/
		} 
		
		version(/+$DIDE_REGION+/all) {
			bool cut_impl2(bool dontMeasure=false)(TextSelection[] sel, ref TextSelection[] res)
			{
				//Todo: constness for input
				bool success; 
				auto tmp = cut_impl!dontMeasure(sel, &success); 
				if(success) res = tmp; 
				return success; 
			} 
			
			///All operations must go through copy_impl or cut_impl. Those are calling 
			///requestModifyPermission and blocks modifications when the module is readonly. Also that is needed for UNDO.
			bool copy_impl(TextSelection[] textSelections)
			{
				//copy_impl ///////////////////////////////////////
				assert(textSelections.map!"a.valid".all && textSelections.isSorted); //Todo: merge check
				
				auto s = textSelections.sourceText; //this can throw if structured declarations has invalid contents
				
				//Bug: Two adjacent slashComnments are not emit a newLine in between them
				
				bool valid = s.length>0; 
				if(valid) clipboard.text = s; 
				return valid; 
			} 
		}
		
		//Todo: Make a version of copy/cut/paste that works with CodeColumns (multiple rows)
		//Todo: For this CodeColumn deep copy must be implemented somehow.  //Maybe by exporting and rendering it again. Speed is not important
		auto paste_impl(bool dontMeasure=false)(
			TextSelection[] textSelections,
			string input,
			Flag!"duplicateTabs" duplicateTabs = No.duplicateTabs,
			Flag!"isObject" isObject = No.isObject,
			int objectSubColumnIdx = 0,
			TextFormat objectTextFormat = TextFormat.managed_block
		)
		{
			if(input=="" || textSelections.empty) return textSelections; //no target
			
			assert(textSelections.map!"a.valid".all && textSelections.isSorted); //Todo: merge check
			
			//Todo: BOM handling
			
			string[] lines; 
			
			if(isObject)
			{
				const source = input.replace("\0", ""); 
				//syntaxCheck(source);   not good for expressions, only good for blocks.
				auto testCol = new CodeColumn(null, source, objectTextFormat); 
				enforce(testCol.byCell.drop(1).empty, "Object insert: Column must have only 1 object. "~source.quoted~" "~objectTextFormat.text); 
				auto testNode = cast(CodeNode) testCol.byCell.frontOrNull; 
				auto testGlyph = cast(Glyph) testCol.byCell.frontOrNull; 
				enforce(testNode || testGlyph, "Object insert: CodeNode expected."); 
				//Todo: clean this mess up, allow multiple glyphs and later multiline glyphs!
				
				lines = textSelections.map!"a.sourceText".array; 
				//this will be the content inserted into the object
			}
			else
			{ lines = input.splitLines; }
			
			if(lines.empty) return textSelections; //nothing to do with an empty clipboard
			
			if(!cut_impl2!dontMeasure(textSelections, /+writes into this if successful -> +/textSelections))
			{
				//Todo: this is terrible. Must refactor.
				return textSelections; 
			}
			
			//from here it's paste -------------------------------------------------
			undoGroupId++; 
			
			TextSelectionReference[] savedSelections; 
			
			//Todo: insertText with fake local syntax highlighting. until the background syntax highlighter finishes.
			
			///inserts text at cursor, moves the corsor to the end of the text
			void insertSingleLine(ref TextSelection ts, string str)
			{
				assert(ts.valid); 
				assert(ts.isZeroLength); 
				assert(ts.caret.pos.y.inRange(ts.codeColumn.subCells)); 
				
				if(auto row = ts.codeColumn.getRow(ts.caret.pos.y))
				{
					if(requestInsertPermission_prepare(ts, str))
					{
						int insertedCnt; 
						TextCursor updatedCursor; 
						
						if(isObject)
						{
							const source = input.replace("\0", str); 
							try
							{
								auto col = new CodeColumn(null, source, objectTextFormat); 
								
								if(auto node = col.extractSingleNode.ifThrown(null))
								{
									insertedCnt = row.insertSomething(
										ts.caret.pos.x, {
											node.setParent(row); 
											row.append(node); 
										}
									); 
									
									node.measure; //regenerates subColumns
									if(objectSubColumnIdx>=0)
									if(auto subCol = node.subColumns.array.get(objectSubColumnIdx))
									updatedCursor = subCol.endCursor; 
								}
								else if(auto glyph = (cast(Glyph)(col.byCell.frontOrNull)))
								{
									//Todo: support multiple glyphs AKA source text
									insertedCnt = row.insertSomething(ts.caret.pos.x, { row.append(glyph); }); 
								}
								else raise("Unhandled sourceCone node template"); 
							}
							catch(Exception e)
							{
								im.flashWarning("Error inserting CodeNode:"~e.simpleMsg); 
								insertedCnt = row.insertText(ts.caret.pos.x, source); 
							}
						}
						else
						{ insertedCnt = row.insertText(ts.caret.pos.x, str); }
						//INS
						
						
						//adjust caret and save
						ts.cursors[0].moveRight(insertedCnt); 
						ts.cursors[1] = ts.cursors[0]; 
						
						requestInsertPermission_finish(ts); 
						needResyntax(ts.codeColumn); 
						ts.codeColumn.edited = true; 
						
						if(updatedCursor.valid)
						{ ts.cursors[] = updatedCursor; }
					}
					
					savedSelections ~= ts.toReference; 
				}
				else
				assert(0, "Row out if range"); 
			} 
			
			void insertMultiLine(ref TextSelection ts, string[] lines )
			{
				assert(ts.valid); 
				assert(ts.isZeroLength); 
				assert(lines.length>=2); 
				
				if(auto row = ts.codeColumn.getRow(ts.caret.pos.y))
				{
					assert(ts.caret.pos.x>=0 && ts.caret.pos.x<=row.subCells.length); 
					
					//handle leadingTab duplication
					if(duplicateTabs && row.leadingCodeTabCount)
					{
						const newTabCnt = min(row.leadingCodeTabCount, ts.caret.pos.x); 
						
						lines = lines.dup; 
						lines.back = "\t".replicate(newTabCnt) ~ lines.back; 
					}
					
					if(requestInsertPermission_prepare(ts, lines.join(DefaultNewLine)))
					{
						//break the row into 2 parts
						//transfer the end of (first)row into a lastRow
						auto lastRow = row.splitRow(ts.caret.pos.x); 
						
						//insert at the end of the first row
						row.insertText(row.cellCount, lines.front);  //INS
						
						//create extra rows in the middle
						Cell[] midRows; 
						foreach(line; lines[1..$-1])
						{
							auto r = new CodeRow(ts.codeColumn, line);  //INS
							//Todo: this should be insertText
							r.setChangedCreated; 
							midRows ~= r; 
						}
						
						//insert at the beginning of the last row
						const insertedCnt = lastRow.insertText(0, lines.back);  //INS
						
						//insert modified rows into column
						ts.codeColumn.subCells 	= ts.codeColumn.subCells[0..ts.caret.pos.y+1]
							~ midRows
							~ lastRow
							~ ts.codeColumn.subCells[ts.caret.pos.y+1..$]; 
						
						//adjust caret and save as reference
						ts.cursors[0].pos.y += lines.length.to!int-1; 
						ts.cursors[0].pos.x = insertedCnt; 
						ts.cursors[1] = ts.cursors[0]; 
						
						requestInsertPermission_finish(ts); 
						needResyntax(ts.codeColumn); 
						ts.codeColumn.edited = true; 
					}
					
					savedSelections ~= ts.toReference; 
					
					//Todo: update caret
				}
				else
				assert(0, "Row out if range"); 
			} 
			
			///insert all lines into the selection
			void fullInsert(ref TextSelection ts)
			{
				if(lines.length==1)
				{
					//simple text without newline
					insertSingleLine(ts, lines[0]); 
				}
				else if(lines.length>1)
				{
					//insert multiline text
					insertMultiLine(ts, lines); 
				}
			} 
			
			if(textSelections.length==1)
			{
				//put all the clipboard into one place
				fullInsert(textSelections[0]); 
			}
			else if(textSelections.length>1)
			{
				if(lines.length>textSelections.length || duplicateTabs/+this means it is pasting newlines+/)
				{
					//clone the full clipboard into all selections.
					foreach_reverse(ref ts; textSelections)
					fullInsert(ts); 
				}
				else
				{
					//cyclically paste the lines of the clipboard
					foreach_reverse(ref ts, line; lockstep(textSelections, lines.cycle.take(textSelections.length)))
					insertSingleLine(ts, line); 
				}
			}
			
			static if(!dontMeasure) modules.workspaceContainer.measure/+It's needed to calculate TextCursor.desiredX+/; 
			//Opt: measure is terribly slow when editing het.utils. 8ms in debug. SavedSelections are not required all the time.
			
			return savedSelections.retro.map!"a.fromReference".filter!"a.valid".array; 
			
			/+Bug: must not fail when text selected inside error messages!+/
		} 
		
		void pasteText(string s)
		{ if(s!="") textSelections.items = paste_impl(textSelections[], s); }  void insertNode(string source, int subColumnIdx=-1)
		{
			textSelections.items = paste_impl(
				textSelections[], source, No.duplicateTabs, 
				Yes.isObject, subColumnIdx, TextFormat.managed_optionalBlock
			); 
		} 
		
	}version(/+$DIDE_REGION Feed, SyntaxtCheck+/all)
	{
		enum syntaxCheckTempFile = File(`z:\temp\__syntax.d`); //Todo: to settings!
		
		void syntaxCheck(File moduleFile, string source, int lineIdx=1)
		{
			{
				/+
					Todo: The error can be in another imported module too, not just this module. 
					But the error file is wrongly renamed to this file.
				+/
				
				static bool[string] simpleValids; 
				if(simpleValids.empty)
				["{}", "q{}", "[]", "()", "``", "''", `""`].each!((s){ simpleValids[s]=true; }); 
				
				if(source in simpleValids) return; 
			}
			
			auto f = syntaxCheckTempFile; 
			f.write(format!"#line %d\nversion(none):%s"(max(lineIdx, 1), source)); 
			auto cmd = ["ldc2", "-c", "-o-", "-vcolumns", "-verrors-context", f.fullName]; 
			auto ex = executeShell(cmd.joinCommandLine, null, ExecuteConfig.suppressConsole); 
			f.remove; 
			if(ex.status!=0)
			{
				string output = ex.output; 
				
				{
					//replace filenames
					const fOld = f.fullName.toLower~"("; 
					const fNew = moduleFile.fullName~"("; 
					output = output	.splitLines
						.map!(s=>((s.map!toLower.startsWith(fOld)) ?(fNew~s[fOld.length..$]) :(s)))
						.filter!(s=>!s.endsWith("): Error: declaration expected, not `module`"))
						.join('\n'); 
					//LOG(output); 
				}
				
				enforce(buildServices.ready); 
				auto messages = decodeDMDMessages(output, moduleFile); 
				buildMessages.process(messages); 
				
				const errIdx = messages.countUntil!((m)=>(m.type==DMDMessage.Type.error)); 
				if(errIdx>=0)
				raise(messages[errIdx].oneLineText); 
			}
		} 
		
		void syntaxCheck(string source, int lineIdx=1)
		{ syntaxCheck(File(`c:\$unknown$.d`), source, lineIdx); } 
		
		CodeNode[] editedBreadcrumbNodes(CodeNode rootNode)
		{
			CodeNode[] res; 
			bool[CodeNode] added; 
			void visit(CodeNode node)
			{
				if(!node) return; 
				//visit all [changed] and collect the [edited] ones.
				//Forward order, root nodes at the front.
				if(!node.changed) return; 
				bool anyColEdited = node.subColumns.map!(a=>a.edited).any; 
				if(anyColEdited)
				{
					if(auto n = node.nearestDeclarationBlock)
					if(n !in added)
					{
						res ~= n; 
						added[n]=true; 
					}
				}
				foreach(col; node.subColumns.filter!(a=>a && a.changed))
				{
					anyColEdited |= col.edited; 
					foreach(row; col.rows.filter!(a=>a && a.changed))
					foreach(
						subNode; row.subCells	.map!(a=>cast(CodeNode)a)
							.filter!(a=>a && a.changed)
					)
					visit(subNode); 
				}
			} 
			
			visit(rootNode); 
			if(res.length<=1) return res; 
			
			res = res.retro.array; 
			//root is at the end of list.
			//filter redundant leafs
			const len = res.length.to!int; 
			foreach(i; 0..len-1)
			inner: foreach(j; i+1..len)
			if(res[i].allParents!CodeNode.canFind(res[j]))
			{ res[i] = null;  break inner; }
			
			res = res.filter!"a".array; 
			
			return res; 
		} 
		
		void feedChangedModule(Module mod, Flag!"syntaxCheck" enableSyntaxCheck = Yes.syntaxCheck)
		{
			if(!mod) return; 
			if(!mod.changed) return; 
			if(!mod.isManaged) return; 
			enforce(buildServices.ready, "BuildSystem is currently working."); 
			
			//reset all caches in Module
			mod.resetBuildMessages; 
			mod.resetSearchResults; 
			buildMessages.firstErrorMessageArrived = true; 
			
			void feedNode(CodeNode oldNode)
			{
				oldNode.enforce("Unable to reach node."); 
				auto mod = (cast(Module)(oldNode)); 
				if(!mod) mod = moduleOf(oldNode); 
				mod.enforce("Unable to reach module."); 
				enforce(!mod.isReadOnly, "Module is readonly"); 
				enforce(mod.isManaged, "Module Structure Level must be Managed."); 
				
				const source = oldNode.sourceText; 
				
				if(enableSyntaxCheck) syntaxCheck(mod.file, source, oldNode.lineIdx); 
				auto newCol = new CodeColumn(mod, source, TextFormat.managed_block); 
				
				if(mod is oldNode)
				{
					mod.content.setParent = null; 
					mod.content = newCol; 
					mod.content.setParent = mod; //Todo: Safe parent/child reowning system.
					
					mod.setChanged; 
					mod.measure;  //this will rebuild subCells
				}
				else
				{
					//reload an internal structured object only.
					auto newNode = newCol.extractSingleNode; 
					
					enforce(
						typeid(oldNode)==typeid(newNode), 
						format!"Node typeid mismatch (old:%s, new:%s)"(typeid(oldNode), typeid(newNode))
					); 
					
					auto row = (cast(CodeRow)(oldNode.parent)).enforce("Can't get Node's Row"); 
					const charIdx = row.subCells.countUntil(oldNode); enforce(charIdx>=0, "Can't find Node in Row."); 
					
					oldNode.setParent = null; 
					newNode.setParent(row); 
					row.subCells[charIdx] = newNode; 
					
					row.setChanged; 
					row.measure; //this will rebuild subCells
					row.refreshTabIdx; 
					row.spreadElasticNeedMeasure; 
				}
			} 
			
			foreach(n; editedBreadcrumbNodes(mod)) feedNode(n); 
		} 
		
		void feedAndSaveModules(R)(R modules, Flag!"syntaxCheck" syntaxCheck = Yes.syntaxCheck)
		{
			textSelections.preserve(
				{
					modules.each!((m){ feedChangedModule(m, syntaxCheck); }); 
					modules.each!"a.save"; 
				}
			); 
		} 
	}
} 