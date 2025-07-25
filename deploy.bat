@echo off

rem https://tecadmin.net/create-filename-with-datetime-windows-batch-script/

set YYYY=%date:~0,4%
set YY=%date:~2,2%
set MM=%date:~5,2%
set DD=%date:~8,2%

set HH=%time:~0,2%
if %HH% lss 10 (set HH=0%time:~1,1%)
set NN=%time:~3,2%
set SS=%time:~6,2%
set MS=%time:~9,2%

set TIMESTAMP=%YY%%MM%%DD%T%HH%%NN%

echo Deploying at %date% on %time%

SET RARFILE=dide_%TIMESTAMP%.rar
SET RAREXE="%ProgramFiles%\WinRAR\Rar.exe"

echo Creating backup: RARFILE

%RAREXE% a %RARFILE% dide.exe dide.map dide.d dideModule.d BuildSys.d

copy dide.exe dide_dev.exe
copy dide.map dide_dev.map
copy dide.pdb dide_dev.pdb
copy dide.exe dide_2.exe
copy dide.map dide_2.map
copy dide.pdb dide_2.pdb

rem Cant delete dide.pdb bugfix
del dide.pdb