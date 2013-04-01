Option Compare Database
Option Explicit

' Access Module `AppCodeImportExport`
' -----------------------------------
'
' https://github.com/bkidwell/msaccess-vcs-integration
'
' Brendan Kidwell
' This code is licensed under BSD-style terms.
'
' This is some code for importing and exporting Access Queries, Forms,
' Reports, Macros, and Modules to and from plain text files, for the
' purpose of syncing with a version control system.
'
'
' Use:
'
' BACKUP YOUR WORK BEFORE TRYING THIS CODE!
'
' To create and/or overwrite source text files for all database objects
' (except tables) in "$database-folder/source/", run
' `ExportAllSource()`.
'
' To load and/or overwrite  all database objects from source files in
' "$database-folder/source/", run `ImportAllSource()`.
'
' See project home page (URL above) for more information.
'
'
' Future expansion:
' * Maybe integrate into a dialog box triggered by a menu item.
' * Warning of destructive overwrite.


' --------------------------------
' List of lookup tables that are part of the program rather than the
' data, to be exported with source code
'
' Provide a comman separated list of table names, or an empty string
' ("") if no tables are to be exported with the source code.
' --------------------------------

Private Const INCLUDE_TABLES = ""

Private Type BinFile
    file_num As Integer
    file_len As Long
    file_pos As Long
    buffer As String
    buffer_len As Integer
    buffer_pos As Integer
    at_eof As Boolean
    mode As String
End Type

' --------------------------------
' Constants
' --------------------------------

Const ForReading = 1, ForWriting = 2, ForAppending = 8
Const TristateTrue = -1, TristateFalse = 0, TristateUseDefault = -2

' --------------------------------
' Module variables
' --------------------------------

Private UsingUcs2_Result As String

' --------------------------------
' Beginning of main functions of this module
' --------------------------------

Private Function BinOpen(file_path As String, mode As String) As BinFile
    Dim f As BinFile
    
    f.file_num = FreeFile
    f.mode = LCase(mode)
    If f.mode = "r" Then
        Open file_path For Binary Access Read As f.file_num
        f.file_len = LOF(f.file_num)
        f.file_pos = 0
        If f.file_len > &H4000 Then
            f.buffer = String(&H4000, " ")
            f.buffer_len = &H4000
        Else
            f.buffer = String(f.file_len, " ")
            f.buffer_len = f.file_len
        End If
        f.buffer_pos = 0
        Get f.file_num, f.file_pos + 1, f.buffer
    Else
        DelIfExist file_path
        Open file_path For Binary Access Write As f.file_num
        f.file_len = 0
        f.file_pos = 0
        f.buffer = String(&H4000, " ")
        f.buffer_len = 0
        f.buffer_pos = 0
    End If
    
    BinOpen = f
End Function

Private Function BinRead(ByRef f As BinFile) As Integer
    If f.at_eof = True Then
        BinRead = 0
        Exit Function
    End If
    
    BinRead = Asc(Mid(f.buffer, f.buffer_pos + 1, 1))
    
    f.buffer_pos = f.buffer_pos + 1
    If f.buffer_pos >= f.buffer_len Then
        f.file_pos = f.file_pos + &H4000
        If f.file_pos >= f.file_len Then
            f.at_eof = True
            Exit Function
        End If
        If f.file_len - f.file_pos > &H4000 Then
            f.buffer_len = &H4000
        Else
            f.buffer_len = f.file_len - f.file_pos
            f.buffer = String(f.buffer_len, " ")
        End If
        f.buffer_pos = 0
        Get f.file_num, f.file_pos + 1, f.buffer
    End If
End Function

Private Sub BinWrite(ByRef f As BinFile, b As Integer)
    Mid(f.buffer, f.buffer_pos + 1, 1) = Chr(b)
    f.buffer_pos = f.buffer_pos + 1
    If f.buffer_pos >= &H4000 Then
        Put f.file_num, , f.buffer
        f.buffer_pos = 0
    End If
End Sub

Private Sub BinClose(ByRef f As BinFile)
    If f.mode = "w" And f.buffer_pos > 0 Then
        f.buffer = Left(f.buffer, f.buffer_pos)
        Put f.file_num, , f.buffer
    End If
    Close f.file_num
End Sub

Private Function ProjectPath() As String
    ProjectPath = CurrentProject.Path
    If Right(ProjectPath, 1) <> "\" Then ProjectPath = ProjectPath & "\"
End Function

Private Function TempFile() As String
    TempFile = ProjectPath() & "AppCodeImportExport.tempdata"
End Function

Private Sub ExportObject(obj_type_num As Integer, obj_name As String, file_path As String, _
    Optional Ucs2Convert As Boolean = False)
        
    MkDirIfNotExist Left(file_path, InStrRev(file_path, "\"))
    If Ucs2Convert Then
        Application.SaveAsText obj_type_num, obj_name, TempFile()
        ConvertUcs2Utf8 TempFile(), file_path
    Else
        Application.SaveAsText obj_type_num, obj_name, file_path
    End If
End Sub

Private Sub ImportObject(obj_type_num As Integer, obj_name As String, file_path As String, _
    Optional Ucs2Convert As Boolean = False)
    
    If Ucs2Convert Then
        ConvertUtf8Ucs2 file_path, TempFile()
        Application.LoadFromText obj_type_num, obj_name, TempFile()
    Else
        Application.LoadFromText obj_type_num, obj_name, file_path
    End If
End Sub

Private Sub ConvertUcs2Utf8(source As String, dest As String)
    Dim f_in As BinFile, f_out As BinFile
    Dim in_low As Integer, in_high As Integer

    f_in = BinOpen(source, "r")
    f_out = BinOpen(dest, "w")
    
    Do While Not f_in.at_eof
        in_low = BinRead(f_in)
        in_high = BinRead(f_in)
        If in_high = 0 And in_low < &H80 Then
            ' U+0000 - U+007F   0LLLLLLL
            BinWrite f_out, in_low
        ElseIf in_high < &H80 Then
            ' U+0080 - U+07FF   110HHHLL 10LLLLLL
            BinWrite f_out, &HC0 + ((in_high And &H7) * &H4) + ((in_low And &HC0) / &H40)
            BinWrite f_out, &H80 + (in_low And &H3F)
        Else
            ' U+0800 - U+FFFF   1110HHHH 10HHHHLL 10LLLLLL
            BinWrite f_out, &HE0 + ((in_high And &HF0) / &H10)
            BinWrite f_out, &H80 + ((in_high And &HF) * &H4) + ((in_low And &HC0) / &H40)
            BinWrite f_out, &H80 + (in_low And &H3F)
        End If
    Loop

    BinClose f_in
    BinClose f_out
End Sub

Private Sub ConvertUtf8Ucs2(source As String, dest As String)
    Dim f_in As BinFile, f_out As BinFile
    Dim in_1 As Integer, in_2 As Integer, in_3 As Integer
    
    f_in = BinOpen(source, "r")
    f_out = BinOpen(dest, "w")
    
    Do While Not f_in.at_eof
        in_1 = BinRead(f_in)
        If (in_1 And &H80) = 0 Then
            ' U+0000 - U+007F   0LLLLLLL
            BinWrite f_out, in_1
            BinWrite f_out, 0
        ElseIf (in_1 And &HE0) = &HC0 Then
            ' U+0080 - U+07FF   110HHHLL 10LLLLLL
            in_2 = BinRead(f_in)
            BinWrite f_out, ((in_1 And &H3) * &H40) + (in_2 And &H3F)
            BinWrite f_out, (in_1 And &H1C) / &H4
        Else
            ' U+0800 - U+FFFF   1110HHHH 10HHHHLL 10LLLLLL
            in_2 = BinRead(f_in)
            in_3 = BinRead(f_in)
            BinWrite f_out, ((in_2 And &H3) * &H40) + (in_3 And &H3F)
            BinWrite f_out, ((in_1 And &HF) * &H10) + ((in_2 And &H3C) / &H4)
        End If
    Loop
    
    BinClose f_in
    BinClose f_out
End Sub

Public Sub TestExportUcs2()
    ExportObject acForm, "example_form", ProjectPath & "output.txt", True
    ConvertUtf8Ucs2 ProjectPath & "output.txt", ProjectPath & "output_ucs2.txt"
End Sub

' Determine if this database imports/exports code as UCS-2-LE
Private Function UsingUcs2() As Boolean
    Dim obj_name As String, i As Integer, obj_type As Variant, fn As Integer, bytes As String
    Dim obj_type_split() As String, obj_type_name As String, obj_type_num As Integer
    Dim db As Object ' DAO.Database

    If UsingUcs2_Result <> "" Then
        UsingUcs2 = (UsingUcs2_Result = "1")
        Exit Function
    End If
    
    If CurrentDb.QueryDefs.Count > 0 Then
        obj_type_num = acQuery
        obj_name = CurrentDb.QueryDefs(1).Name
    Else
        For Each obj_type In Split( _
            "Forms|" & acForm & "," & _
            "Reports|" & acReport & "," & _
            "Scripts|" & acMacro & "," & _
            "Modules|" & acModule _
        )
            obj_type_split = Split(obj_type, "|")
            obj_type_name = obj_type_split(0)
            obj_type_num = Val(obj_type_split(1))
            If CurrentDb.Containers(obj_type_name).Documents.Count > 0 Then
                obj_name = CurrentDb.Containers(obj_type_name).Documents(1).Name
                Exit For
            End If
        Next
    End If
    
    If obj_name = "" Then
        ' No objects found that can be used to test UCS2 versus UTF-8
        UsingUcs2_Result = "1"
        UsingUcs2 = True
        Exit Function
    End If

    Application.SaveAsText obj_type_num, obj_name, TempFile()
    fn = FreeFile
    Open TempFile() For Binary Access Read As fn
    bytes = "  "
    Get fn, 1, bytes
    If Asc(Mid(bytes, 1, 1)) = &HFF And Asc(Mid(bytes, 2, 1)) = &HFE Then
        UsingUcs2_Result = "1"
        UsingUcs2 = True
    Else
        UsingUcs2_Result = "0"
        UsingUcs2 = False
    End If
    Close fn
End Function

Public Sub TestUsingUcs2()
    UsingUcs2_Result = ""
    Debug.Print UsingUcs2()
End Sub

' Create folder `Path`. Silently do nothing if it already exists.
Private Sub MkDirIfNotExist(Path As String)
    On Error GoTo MkDirIfNotexist_noop
    MkDir Path
MkDirIfNotexist_noop:
    On Error GoTo 0
End Sub

' Delete a file if it exists.
Private Sub DelIfExist(Path As String)
    On Error GoTo DelIfNotExist_Noop
    Kill Path
DelIfNotExist_Noop:
    On Error GoTo 0
End Sub

' Erase all *.data and *.txt files in `Path`.
Private Sub ClearTextFilesFromDir(Path As String, Ext As String)
    Dim fso As Object
    Set fso = CreateObject("Scripting.FileSystemObject")
    If Not fso.FolderExists(Path) Then Exit Sub
    
    On Error GoTo ClearTextFilesFromDir_noop
    If Dir(Path & "*." & Ext) <> "" Then
        Kill Path & "*.data" & Ext
    End If
ClearTextFilesFromDir_noop:
    
    On Error GoTo 0
End Sub

' For each *.txt in `Path`, find and remove a number of problematic but
' unnecessary lines of VB code that are inserted automatically by the
' Access GUI and change often (we don't want these lines of code in
' version control).
Private Sub SanitizeTextFiles(Path As String, Ext As String)
    Dim fso, InFile, OutFile, FileName As String, txt As String, obj_name As String
    
    Dim ForReading As Long
    
    ForReading = 1
    Set fso = CreateObject("Scripting.FileSystemObject")
    
    FileName = Dir(Path & "*." & Ext)
    Do Until Len(FileName) = 0
        obj_name = Mid(FileName, 1, InStrRev(FileName, ".") - 1)
        
        Set InFile = fso.OpenTextFile(Path & obj_name & "." & Ext, ForReading)
        Set OutFile = fso.CreateTextFile(Path & obj_name & ".sanitize", True)
        Do Until InFile.AtEndOfStream
            txt = InFile.ReadLine
            If Left(txt, 10) = "Checksum =" Then
                ' Skip lines starting with Checksum
            ElseIf InStr(txt, "NoSaveCTIWhenDisabled =1") Then
                ' Skip lines containning NoSaveCTIWhenDisabled
            ElseIf InStr(txt, "PrtDevNames = Begin") > 0 Or _
                InStr(txt, "PrtDevNamesW = Begin") > 0 Or _
                InStr(txt, "PrtDevModeW = Begin") > 0 Or _
                InStr(txt, "PrtDevMode = Begin") > 0 Then
    
                ' skip this block of code
                Do Until InFile.AtEndOfStream
                    txt = InFile.ReadLine
                    If InStr(txt, "End") Then Exit Do
                Loop
            Else
                OutFile.WriteLine txt
            End If
        Loop
        OutFile.Close
        InFile.Close
        
        FileName = Dir()
    Loop
    
    FileName = Dir(Path & "*." & Ext)
    Do Until Len(FileName) = 0
        obj_name = Mid(FileName, 1, InStrRev(FileName, ".") - 1)
        Kill Path & obj_name & "." & Ext
        Name Path & obj_name & ".sanitize" As Path & obj_name & "." & Ext
        FileName = Dir()
    Loop
End Sub

' Main entry point for EXPORT. Export all forms, reports, queries,
' macros, modules, and lookup tables to `source` folder under the
' database's folder.
Public Sub ExportAllSource()
    Dim db As Object ' DAO.Database
    Dim source_path As String
    Dim obj_path As String
    Dim qry As Object ' DAO.QueryDef
    Dim doc As Object ' DAO.Document
    Dim obj_type As Variant
    Dim obj_type_split() As String
    Dim obj_type_label As String
    Dim obj_type_name As String
    Dim obj_type_num As Integer
    Dim ucs2 As Boolean
    Dim tblName As Variant
    
    Set db = CurrentDb
    
    source_path = ProjectPath() & "source\"
    MkDirIfNotExist source_path
    
    Debug.Print
    
    obj_path = source_path & "queries\"
    ClearTextFilesFromDir obj_path, "bas"
    Debug.Print "Exporting queries..."
    For Each qry In db.QueryDefs
        If Left(qry.Name, 1) <> "~" Then
            ExportObject acQuery, qry.Name, obj_path & qry.Name & ".bas", UsingUcs2()
        End If
    Next
    
    obj_path = source_path & "tables\"
    ClearTextFilesFromDir obj_path, "txt"
    Debug.Print "Exporting tables..."
    For Each tblName In Split(INCLUDE_TABLES, ",")
        ExportTable CStr(tblName), obj_path
    Next
    
    For Each obj_type In Split( _
        "forms|Forms|" & acForm & "," & _
        "reports|Reports|" & acReport & "," & _
        "macros|Scripts|" & acMacro & "," & _
        "modules|Modules|" & acModule _
        , "," _
    )
        obj_type_split = Split(obj_type, "|")
        obj_type_label = obj_type_split(0)
        obj_type_name = obj_type_split(1)
        obj_type_num = Val(obj_type_split(2))
        obj_path = source_path & obj_type_label & "\"
        ClearTextFilesFromDir obj_path, "bas"
        Debug.Print "Exporting " & obj_type_label & "..."
        For Each doc In db.Containers(obj_type_name).Documents
            If Left(doc.Name, 1) <> "~" Then
                If obj_type_label = "modules" Then
                    ucs2 = False
                Else
                    ucs2 = UsingUcs2()
                End If
                ExportObject obj_type_num, doc.Name, obj_path & doc.Name & ".bas", ucs2
            End If
        Next
        
        If obj_type_label <> "modules" Then
            SanitizeTextFiles obj_path, "bas"
        End If
    Next
    
    DelIfExist TempFile()
    Debug.Print "Done."
End Sub

' Main entry point for IMPORT. Import all forms, reports, queries,
' macros, modules, and lookup tables from `source` folder under the
' database's folder.
Public Sub ImportAllSource()
    Dim db As Object ' DAO.Database
    Dim source_path As String
    Dim obj_path As String
    Dim qry As Object ' DAO.QueryDef
    Dim doc As Object ' DAO.Document
    Dim obj_type As Variant
    Dim obj_type_split() As String
    Dim obj_type_label As String
    Dim obj_type_name As String
    Dim obj_type_num As Integer
    Dim FileName As String
    Dim obj_name As String
    Dim ucs2 As Boolean
    
    Set db = CurrentDb
    
    source_path = ProjectPath() & "source\"
    MkDirIfNotExist source_path
    
    Debug.Print
    
    obj_path = source_path & "queries\"
    Debug.Print "Importing queries..."
    FileName = Dir(obj_path & "*.bas")
    Do Until Len(FileName) = 0
        obj_name = Mid(FileName, 1, InStrRev(FileName, ".") - 1)
        ImportObject acQuery, obj_name, obj_path & FileName, UsingUcs2()
        FileName = Dir()
    Loop
    
    '' read in table values
    obj_path = source_path & "tables\"
    Debug.Print "Importing tables..."
    FileName = Dir(obj_path & "*.txt")
    Do Until Len(FileName) = 0
        obj_name = Mid(FileName, 1, InStrRev(FileName, ".") - 1)
        ImportTable CStr(obj_name), obj_path
        FileName = Dir()
    Loop
    
    For Each obj_type In Split( _
        "forms|" & acForm & "," & _
        "reports|" & acReport & "," & _
        "macros|" & acMacro & "," & _
        "modules|" & acModule _
        , "," _
    )
        obj_type_split = Split(obj_type, "|")
        obj_type_label = obj_type_split(0)
        obj_type_num = Val(obj_type_split(1))
        obj_path = source_path & obj_type_label & "\"
        Debug.Print "Importing " & obj_type_label & "..."
        FileName = Dir(obj_path & "*.bas")
        Do Until Len(FileName) = 0
            obj_name = Mid(FileName, 1, InStrRev(FileName, ".") - 1)
            If obj_name <> "AppCodeImportExport" Then
                If obj_type_label = "modules" Then
                    ucs2 = False
                Else
                    ucs2 = UsingUcs2()
                End If
                ImportObject obj_type_num, obj_name, obj_path & FileName, ucs2
            End If
            FileName = Dir()
        Loop
    Next
    
    DelIfExist TempFile()
    Debug.Print "Done."
End Sub

' Export the lookup table `tblName` to `source\tables`.
Private Sub ExportTable(tblName As String, obj_path As String)
    Dim fso, OutFile
    Dim rs As Object ' DAO.Recordset
    Dim fieldObj As Object ' DAO.Field
    Dim C As Long, Value As Variant
    
    Set fso = CreateObject("Scripting.FileSystemObject")
    ' open file for writing with Create=True, Unicode=True (USC-2 Little Endian format)
    MkDirIfNotExist obj_path
    Set OutFile = fso.CreateTextFile(obj_path & tblName & ".us2", True, True)
    
    Set rs = CurrentDb.OpenRecordset("export_" & tblName)
    C = 0
    For Each fieldObj In rs.Fields
        If C <> 0 Then OutFile.write vbTab
        C = C + 1
        OutFile.write fieldObj.Name
    Next
    OutFile.write vbCrLf
    
    rs.MoveFirst
    Do Until rs.EOF
        C = 0
        For Each fieldObj In rs.Fields
            If C <> 0 Then OutFile.write vbTab
            C = C + 1
            Value = rs(fieldObj.Name)
            If IsNull(Value) Then
                Value = ""
            Else
                Value = Replace(Value, "\", "\\")
                Value = Replace(Value, vbCrLf, "\n")
                Value = Replace(Value, vbCr, "\n")
                Value = Replace(Value, vbLf, "\n")
                Value = Replace(Value, vbTab, "\t")
            End If
            OutFile.write CStr(Nz(rs(fieldObj.Name), ""))
        Next
        OutFile.write vbCrLf
        rs.MoveNext
    Loop
    rs.Close
    OutFile.Close
    
    ConvertUcs2Utf8 obj_path & tblName & ".us2", obj_path & tblName & ".txt"
    Kill obj_path & tblName & ".us2"
End Sub

' Import the lookup table `tblName` from `source\tables`.
Private Sub ImportTable(tblName As String, obj_path As String)
    Dim db As Object ' DAO.Database
    Dim rs As Object ' DAO.Recordset
    Dim fieldObj As Object ' DAO.Field
    Dim fso, InFile As Object
    Dim C As Long, buf As String, Values() As String, Value As Variant, rsWrite As Recordset
    
    Set fso = CreateObject("Scripting.FileSystemObject")
    ConvertUtf8Ucs2 obj_path & tblName & ".txt", TempFile()
    ' open file for reading with Create=False, Unicode=True (USC-2 Little Endian format)
    Set InFile = fso.OpenTextFile(TempFile(), ForReading, False, TristateTrue)
    Set db = CurrentDb
    
    db.Execute "DELETE FROM [" & tblName & "]"
    Set rs = db.OpenRecordset("export_" & tblName)
    Set rsWrite = db.OpenRecordset(tblName)
    buf = InFile.ReadLine()
    Do Until InFile.AtEndOfStream
        buf = InFile.ReadLine()
        If Len(Trim(buf)) > 0 Then
            Values = Split(buf, vbTab)
            C = 0
            rsWrite.AddNew
            For Each fieldObj In rs.Fields
                Value = Values(C)
                If Len(Value) = 0 Then
                    Value = Null
                Else
                    Value = Replace(Value, "\t", vbTab)
                    Value = Replace(Value, "\n", vbCrLf)
                    Value = Replace(Value, "\\", "\")
                End If
                rsWrite(fieldObj.Name) = Value
                C = C + 1
            Next
            rsWrite.Update
        End If
    Loop
    
    rsWrite.Close
    rs.Close
    InFile.Close
End Sub