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

SET RARFILE=dide2_%TIMESTAMP%.rar
SET RAREXE="%ProgramFiles%\WinRAR\Rar.exe"

echo Creating backup: RARFILE

%RAREXE% a %RARFILE% dide2.exe dide2.map dide2.d dideModule.d

copy dide2.exe dide2_dev.exe
copy dide2.map dide2_dev.map
copy dide2.exe dide2_2.exe
copy dide2.map dide2_2.map