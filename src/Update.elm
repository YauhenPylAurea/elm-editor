module Update exposing (update)

import Action
import Array exposing (Array)
import ArrayUtil
import Browser.Dom as Dom
import Cmd.Extra exposing (withCmd, withCmds, withNoCmd)
import Common exposing (..)
import ContextMenu exposing (ContextMenu)
import Debounce exposing (Debounce)
import EditorModel exposing (AutoLineBreak(..), EditMode(..), EditorModel, Snapshot, VimMode(..))
import EditorMsg exposing (EMsg(..), Hover(..), Position, Selection(..))
import History
import Search
import Task exposing (Task)
import Update.File
import Update.Function as Function
import Update.Group
import Update.Line
import Update.Scroll
import Update.Wrap


update : EMsg -> EditorModel -> ( EditorModel, Cmd EMsg )
update msg model =
    case msg of
        EditorNoOp ->
            ( model, Cmd.none )

        ExitVimInsertMode ->
            { model | editMode = VimEditor VimNormal }
                |> withNoCmd

        Test ->
            Action.goToLine 30 model

        DebounceMsg msg_ ->
            let
                ( debounce, cmd ) =
                    Debounce.update
                        EditorModel.debounceConfig
                        (Debounce.takeLast Function.unload)
                        msg_
                        model.debounce
            in
            ( { model | debounce = debounce }, cmd )

        Unload _ ->
            ( { model | debounce = model.debounce }, Cmd.none )

        MoveUp ->
            Action.cursorUp model
                |> recordHistory_ model
                |> withNoCmd

        MoveDown ->
            Action.cursorDown model
                |> recordHistory_ model
                |> withNoCmd

        MoveLeft ->
            Action.cursorLeft model
                |> recordHistory_ model
                |> withNoCmd

        MoveRight ->
            Action.cursorRight model
                |> recordHistory_ model
                |> withNoCmd

        NewLine ->
            (Function.newLine model |> Common.sanitizeHover)
                |> (\m -> ( m, Update.Scroll.jumpToBottom m ))

        InsertChar char ->
            let
                ( debounce, debounceCmd ) =
                    Debounce.push EditorModel.debounceConfig char model.debounce
            in
            Function.insertChar model.editMode char { model | debounce = debounce }
                |> withCmd debounceCmd
                |> recordHistoryWithCmd model

        Indent ->
            model
                |> Action.indent
                |> recordHistory_ model
                |> withNoCmd

        Deindent ->
            model
                |> Action.deIndent
                |> recordHistory_ model
                |> withNoCmd

        KillLine ->
            let
                lineNumber =
                    model.cursor.native.line

                lastColumnOfLine =
                    Array.get lineNumber model.lines
                        |> Maybe.map String.length
                        |> Maybe.withDefault 0
                        |> (\x -> x - 1)

                lineEnd =
                    { line = lineNumber, column = lastColumnOfLine }

                newSelection =
                    Selection model.cursor.native lineEnd

                ( newLines, selectedText ) =
                    Action.deleteSelection newSelection model.lines
            in
            ( { model | lines = newLines, selectedText = selectedText }, Cmd.none )
                |> recordHistoryWithCmd model

        DeleteLine ->
            let
                lineNumber =
                    model.cursor.native.line

                newCursor =
                    {native = { line = lineNumber, column = 0 }, foreign = model.cursor.foreign}

                lastColumnOfLine =
                    Array.get lineNumber model.lines
                        |> Maybe.map String.length
                        |> Maybe.withDefault 0
                        |> (\x -> x - 1)

                lineEnd =
                    { line = lineNumber, column = lastColumnOfLine }

                newSelection =
                    Selection newCursor.native lineEnd

                ( newLines, selectedText ) =
                    Action.deleteSelection newSelection model.lines
            in
            ( { model | lines = newLines, selectedText = selectedText }, Cmd.none )
                |> recordHistoryWithCmd model

        Cut ->
            Function.deleteSelection model
                |> recordHistoryWithCmd model

        Copy ->
            Function.copySelection model

        Paste ->
            Function.pasteSelection model
                |> recordHistory

        RemoveCharBefore ->
            Function.deleteSelection model
                |> recordHistoryWithCmd model

        FirstLine ->
            Action.firstLine model

        Hover hover ->
            ( { model | hover = hover }
                |> Common.sanitizeHover
            , Cmd.none
            )

        GoToHoveredPosition ->
            ( { model
                | cursor =
                    case model.hover of
                        NoHover ->
                            model.cursor

                        HoverLine line ->
                            { native = { line = line , column = lastColumn model.lines line }, foreign = model.cursor.foreign}

                        HoverChar position ->
                           {native = position, foreign = model.cursor.foreign}
              }
            , Cmd.none
            )

        LastLine ->
            Action.lastLine model

        AcceptLineToGoTo str ->
            ( { model | lineNumberToGoTo = str }, Cmd.none )

        GoToLine ->
            case String.toInt model.lineNumberToGoTo of
                Nothing ->
                    ( model, Cmd.none )

                Just n ->
                    Action.goToLine n model

        RemoveCharAfter ->
            ( removeCharAfter model
                |> Common.sanitizeHover
            , Cmd.none
            )
                |> recordHistoryWithCmd model

        StartSelecting ->
            ( { model | selection = SelectingFrom model.hover }
            , Cmd.none
            )

        StopSelecting ->
            -- Selection for all other
            let
                endHover =
                    model.hover

                newSelection =
                    case model.selection of
                        NoSelection ->
                            NoSelection

                        SelectingFrom startHover ->
                            if startHover == endHover then
                                case startHover of
                                    NoHover ->
                                        NoSelection

                                    HoverLine _ ->
                                        NoSelection

                                    HoverChar position ->
                                        SelectedChar position

                            else
                                hoversToPositions model.lines startHover endHover
                                    |> Maybe.map (\( from, to ) -> Selection from to)
                                    |> Maybe.withDefault NoSelection

                        SelectedChar _ ->
                            NoSelection

                        Selection _ _ ->
                            NoSelection
            in
            ( { model | selection = newSelection }
            , Cmd.none
            )

        SelectLine ->
            Action.selectLine model

        SelectUp ->
            Action.selectUp model
                |> recordHistory

        SelectDown ->
            Action.selectDown model
                |> recordHistory

        SelectLeft ->
            Action.selectLeft model
                |> recordHistory

        SelectRight ->
            Action.selectRight model
                |> recordHistory

        MoveToLineStart ->
            Action.moveToLineStart model

        MoveToLineEnd ->
            Action.moveToLineEnd model

        PageDown ->
            Action.pageDown model

        PageUp ->
            Action.pageUp model

        Clear ->
            ( { model | lines = Array.fromList [ "" ] }, Cmd.none )

        Undo ->
            case History.undo (Common.stateToSnapshot model) model.history of
                Just ( history, snapshot ) ->
                    ( { model
                        | cursor = snapshot.cursor
                        , selection = snapshot.selection
                        , lines = snapshot.lines
                        , history = history
                      }
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        Redo ->
            case History.redo (Common.stateToSnapshot model) model.history of
                Just ( history, snapshot ) ->
                    ( { model
                        | cursor = snapshot.cursor
                        , selection = snapshot.selection
                        , lines = snapshot.lines
                        , history = history
                      }
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        ContextMenuMsg msg_ ->
            let
                ( contextMenu, cmd ) =
                    ContextMenu.update msg_ model.contextMenu
            in
            ( { model | contextMenu = contextMenu }
            , Cmd.map ContextMenuMsg cmd
            )

        Item k ->
            ( model, Cmd.none )

        WrapSelection ->
            Update.Wrap.selection model |> recordHistory_ model |> withNoCmd

        WrapAll ->
            Update.Wrap.all model |> recordHistory_ model |> withNoCmd

        ToggleAutoLineBreak ->
            case model.autoLineBreak of
                AutoLineBreakOFF ->
                    ( { model | autoLineBreak = AutoLineBreakON }, Cmd.none )

                AutoLineBreakON ->
                    ( { model | autoLineBreak = AutoLineBreakOFF }, Cmd.none )

        EditorRequestFile ->
            ( model, Update.File.requestMarkdownFile )

        EditorRequestedFile file ->
            ( model, Update.File.read file )

        MarkdownLoaded str ->
            ( { model | lines = str |> String.lines |> Array.fromList }, Cmd.none )

        EditorSaveFile ->
            let
                markdown =
                    model.lines
                        |> Array.toList
                        |> String.join "\n"
            in
            ( model, Update.File.save markdown )

        SendLineForLRSync ->
            {- DOC scroll LR entry point (1) -}
            Update.Scroll.sendLine model

        GotViewportForSync str selection result ->
            case result of
                Ok vp ->
                    let
                        y =
                            vp.viewport.y

                        lineNumber =
                            round (y / model.lineHeight)
                    in
                    ( { model | topLine = lineNumber, selection = selection }, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )

        CopyPasteClipboard ->
            {- The msg CopyPasteClipboard is detected and acted upon by the
               host app's update function.
            -}
            ( model, Cmd.none )

        WriteToSystemClipBoard ->
            {- The msg WriteToSystemClipBoard is detected and acted upon by the
               host app's update function.
            -}
            case model.selection of
                Selection p1 p2 ->
                    let
                        selectedString =
                            ArrayUtil.between p1 p2 model.lines

                        newModel =
                            { model | selectedString = Just selectedString }
                    in
                    ( newModel, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        DoSearch key ->
            Search.do key model |> withCmd Cmd.none

        ToggleSearchPanel ->
            -- TODO: FOCUS ON "editor-search-box"
            let
                focusSearchBox : Cmd EMsg
                focusSearchBox =
                    Task.attempt (\_ -> EditorNoOp) (Dom.focus "editor-search-box")
            in
            { model | showSearchPanel = not model.showSearchPanel } |> withCmd focusSearchBox

        ToggleReplacePanel ->
            { model | canReplace = not model.canReplace } |> withNoCmd

        OpenReplaceField ->
            { model | canReplace = True } |> withNoCmd

        RollSearchSelectionForward ->
            Update.Scroll.rollSearchSelectionForward model

        RollSearchSelectionBackward ->
            Update.Scroll.rollSearchSelectionBackward model

        AcceptReplacementText str ->
            { model | replacementText = str } |> withNoCmd

        ReplaceCurrentSelection ->
            case model.selection of
                Selection from to ->
                    let
                        newLines =
                            ArrayUtil.replace model.cursor.native to model.replacementText model.lines
                    in
                    Update.Scroll.rollSearchSelectionForward { model | lines = newLines }

                -- TODO: FIX THIS
                -- |> recordHistory
                _ ->
                    ( model, Cmd.none )

        AcceptLineNumber str ->
            model |> withNoCmd

        AcceptSearchText str ->
            Update.Scroll.toString str model

        GotViewport result ->
            case result of
                Ok vp ->
                    let
                        y =
                            vp.viewport.y

                        lineNumber =
                            round (y / model.lineHeight)
                    in
                    ( { model | topLine = lineNumber }, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )

        ToggleDarkMode ->
            Function.toggleViewMode model |> withNoCmd

        ToggleHelp ->
            Function.toggleHelpState model |> withNoCmd

        ToggleEditMode ->
            Function.toggleEditMode model |> withNoCmd

        MarkdownMsg _ ->
            model |> withNoCmd

        SelectGroup ->
            let
                range =
                    Update.Group.groupRange model.cursor.native model.lines

                line =
                    model.cursor.native.line


            in
            case range of
                Just ( start, end ) ->
                    let
                        native =  {line = line, column = end }
                    in
                    ( { model
                        | cursor = { native = native, foreign = model.cursor.foreign }
                        , selection = Selection { line = line, column = start } { line = line, column = end }
                      }
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )
