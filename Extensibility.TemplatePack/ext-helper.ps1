[cmdletbinding()]
param(
    [Parameter(Position=2)]
    [string]$newtonsoftDownloadUrl = 'http://www.nuget.org/api/v2/package/Newtonsoft.Json/10.0.2',

    [Parameter(Position=3)]
    [string]$newtonsoftFilename = 'Newtonsoft.Json-10.0.2.nupkg'
)

$global:machinesetupconfig = @{
    MachineSetupConfigFolder = (Join-Path $env:temp 'SayedHaMachineSetup')
    MachineSetupAppsFolder = (Join-Path $env:temp 'SayedHaMachineSetup\apps')
    RemoteFiles = (join-path $env:temp 'SayedHaMachineSetup\remotefiles')
    HasLoadedNetwonsoft = $false
}

function ExtractRemoteZip{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$downloadUrl,

        [Parameter(Position=1)]
        [ValidateNotNullOrEmpty()]
        [string]$filename
    )
    process{
        $zippath = GetLocalFileFor -downloadUrl $downloadUrl -filename $filename
        $expectedFolderpath = (join-path -Path ($global:machinesetupconfig.MachineSetupConfigFolder) ('apps\{0}\' -f $filename))

        if(-not (test-path $expectedFolderpath)){
            EnsureFolderExists -path $expectedFolderpath | Write-Verbose
            # extract the folder to the directory
            & (Get7ZipPath) x -y "-o$expectedFolderpath" "$zippath" | Write-Verbose
        }        

        # return the path to the folder
        $expectedFolderpath
    }
}
function GetLocalFileFor{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$downloadUrl,

        [Parameter(Position=1,Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$filename,

        [Parameter(Position=2)]
        [int]$timeoutSec = 60
    )
    process{
        'GetLocalFileFor: url:[{0}] filename:[{1}]' -f $downloadUrl,$filename | Write-Verbose
        $expectedPath = (Join-Path $global:machinesetupconfig.RemoteFiles $filename)
        
        if(-not (test-path $expectedPath)){
            # download the file
            EnsureFolderExists -path ([System.IO.Path]::GetDirectoryName($expectedPath)) | out-null
            Invoke-WebRequest -Uri $downloadUrl -TimeoutSec $timeoutSec -OutFile $expectedPath -ErrorAction SilentlyContinue | Write-Verbose
        }

        if(-not (test-path $expectedPath)){
            throw ('Unable to download file from [{0}] to [{1}]' -f $downloadUrl, $expectedPath)
        }

        $expectedPath
    }
}
function EnsureFolderExists{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [string[]]$path
    )
    process{
        foreach($p in $path){
            if(-not [string]::IsNullOrWhiteSpace($p) -and (-not (Test-Path $p))){
                New-Item -Path $p -ItemType Directory
            }
        }
    }
}
function Get7ZipPath{
    [cmdletbinding()]
    param()
    process{
        (join-path $env:ProgramFiles '7-Zip\7z.exe')
    }
}
function Load-NewtonsoftJson{
    [cmdletbinding()]
    param(
        [Parameter(Position=1)]
        [string]$newtonsoftDownloadUrl = $newtonsoftDownloadUrl,

        [Parameter(Position=2)]
        [string]$newtonsoftFilename = $newtonsoftFilename
    )
    process{
        $extractPath = ExtractRemoteZip -downloadUrl $newtonsoftDownloadUrl -filename $newtonsoftFilename
        $expectedPath = (join-path $extractPath '\lib\net40\Newtonsoft.Json.dll')
        if(-not (test-path $expectedPath)){
            throw ('Unable to load newtonsoft.json from [{0}]' -f $expectedPath)
        }
        'Loading newtonsoft.json from file [{0}]' -f $expectedPath | Write-Verbose
        [Reflection.Assembly]::LoadFile($expectedPath)
        $global:machinesetupconfig.HasLoadedNetwonsoft = $true
    }
}

function UpdateVsTemplateFiles{
    [cmdletbinding()]
    param(
        [string]$sourceRoot = (Join-path $PSScriptRoot '..\')
    )
    process{
        # find each template.json file
        $templateFiles = Get-ChildItem -Path $sourceRoot template.json -recurse -file|Select-object -expandproperty fullname
        $dir = $pwd
        try{
            foreach($tf in $templateFiles ){
                $dir = split-path -path $tf -Parent
                # fix the json file itself first
                $tempjson = ([Newtonsoft.Json.Linq.JObject]::Parse([System.IO.File]::ReadAllText($tf)))
                $tempjson.identity.value='LigerShark.Extensibility.{0}.CSharp' -f ($tempjson.defaultName.value)
                $tempjson.groupIdentity.Value='LigerShark.Extensibility.{0}' -f ($tempjson.defaultName.value)
                $tempjson.ToString() | Out-File -FilePath $tf -Encoding ascii

                [string[]]$vstemplate = (get-childitem -path $dir *.vstemplate|select-object -ExpandProperty fullname)
                if($vstemplate -ne $null -and ($vstemplate.count -eq 1)){



                    # $tempxml=([xml]get-content -path $vstemplate[0])
                    $tempxml = ([xml](get-content $vstemplate))
                    
                    $defaultName = $tempjson.defaultName.value

                    $tempxml.VSTemplate.TemplateData.Description = $tempjson.description.value
                    $tempxml.VSTemplate.TemplateData.Name = $tempjson.name.value.Replace('VS2017 ','')
                    $identity = ("LigerShark.Extensibility.{0}.CSharp" -f $defaultName)
                    $groupId = ("LigerShark.Extensibility.{0}" -f $defaultName)

                    $tempxml.VSTemplate.TemplateContent.CustomParameters.CustomParameter[2].value = $groupId
                    $tempxml.VSTemplate.TemplateData.TemplateID = $identity
                    $tempxml.VSTemplate.TemplateData.DefaultName = $tempjson.defaultName.value
                    $tempxml.Save($vstemplate)
                }
                else{
                    "Unable to process dir:[$dir], vstemplate: [$vstemplate]" | Write-Warning
                }
            }
        }
        catch{
            "Unable to process tf:[$tf] vstemplate:[$vstemplate]" | Write-Warning
            Write-Warning $_
        }
    }
}
function GetGuidsToReplace{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [string]$folderpath = ($pwd),

        [Parameter(Position=1)]
        [string]$guidPattern = '[{(]?[0-9A-F]{8}[-]?([0-9A-F]{4}[-]?){3}[0-9A-F]{12}[)}]?',

        [Parameter(Position=2)]
        [string[]]$pathToExclude = ('packages','bin','obj')
    )
    process{
        # get projectid from all project files, $xml.Project.PropertyGroup.ProjectGuid

        $projectfiles = ((Get-ChildItem -Path $folderpath '*.*proj' -exclude $pathToExclude -Recurse -File)|Select-Object -ExpandProperty fullname)

        foreach($pf in $projectfiles){
            if(test-path -Path $pf -PathType Leaf){
                $pxml = [xml](Get-Content -Path $pf)
                $pguid = $pxml.Project.PropertyGroup.ProjectGuid
                if(-not ([string]::IsNullOrWhiteSpace($pguid))) {
                    $relpf = (InternalGet-RelativePath -fromPath $folderpath -toPath $pf)
                    "// Project ID: - $relpf `r`n""$pguid""," | Write-Output
                }
            }
        }

        $vsixmanifestfiles = ((Get-ChildItem -Path $folderpath '*.vsixmanifest' -exclude $pathToExclude -Recurse -File)|Select-Object -ExpandProperty fullname)
        foreach($vm in $vsixmanifestfiles){
            if(test-path -Path $vm -PathType Leaf){
                $pxml = [xml](Get-Content -Path $vm)
                $vmid = $pxml.PackageManifest.Metadata.Identity.Id
                if(-not ([string]::IsNullOrWhiteSpace($vmid))) {
                    $relvm = (InternalGet-RelativePath -fromPath $folderpath -toPath $vm)
                    "// vsixmanifest ID - $relvm`r`n""$vmid""," | Write-Output
                }
            }
        }

        # generic guid search across files
        Get-ChildItemsExclude -path $folderpath -exclude $pathToExclude | Select-String -Pattern $guidPattern | Select-Object -Unique
    }
}

function Get-ChildItemsExclude{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [string[]]$path,

        [Parameter(Position=1)]
        [string[]]$exclude,

        [Parameter(Position=2)]
        [string]$include
    )
    process{
        [string]$excludePattern = $null
        if(-not ([string]::IsNullOrWhiteSpace($exclude))) {
            $excludePattern = '('
            foreach($ex in $exclude){
                $p = "\\$ex\\|"
                $excludePattern += $p
            }
            $excludePattern = $excludePattern.TrimEnd('|')
            $excludePattern += ')'
        }

        foreach($p in $path){
            if([string]::IsNullOrWhiteSpace($include)){
                $children = Get-ChildItem -Path $p -Recurse -File|Select-Object -ExpandProperty fullname
            }
            else{
                $children = Get-ChildItem -Path $p $include -Recurse -File|Select-Object -ExpandProperty fullname
            }

            if(-not ([string]::IsNullOrWhiteSpace($excludePattern))){
                foreach($c in $children){
                    if(-not ($c -imatch $excludePattern)){
                        $c
                    }
                }
            }
            else{
                $children
            }
        }
    }
}

function InternalGet-RelativePath{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$fromPath,

        [Parameter(Position=0,Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$toPath
    )
    process{
        $fromPathToUse = (Resolve-Path $fromPath).Path
        if( (Get-Item $fromPathToUse) -is [System.IO.DirectoryInfo]){
            $fromPathToUse += [System.IO.Path]::DirectorySeparatorChar
        }

        $toPathToUse = (Resolve-Path $toPath).Path
        if( (Get-Item $toPathToUse) -is [System.IO.DirectoryInfo]){
            $toPathToUse += [System.IO.Path]::DirectorySeparatorChar
        }

        [uri]$fromUri = New-Object -TypeName 'uri' -ArgumentList $fromPathToUse
        [uri]$toUri = New-Object -TypeName 'uri' -ArgumentList $toPathToUse

        [string]$relPath = $toPath
        # if the Scheme doesn't match just return toPath
        if($fromUri.Scheme -eq $toUri.Scheme){
            [uri]$relUri = $fromUri.MakeRelativeUri($toUri)
            $relPath = [Uri]::UnescapeDataString($relUri.ToString())

            if([string]::Equals($toUri.Scheme, [Uri]::UriSchemeFile, [System.StringComparison]::OrdinalIgnoreCase)){
                $relPath = $relPath.Replace([System.IO.Path]::AltDirectorySeparatorChar,[System.IO.Path]::DirectorySeparatorChar)
            }
        }

        if([string]::IsNullOrWhiteSpace($relPath)){
            $relPath = ('.{0}' -f [System.IO.Path]::DirectorySeparatorChar)
        }

        #'relpath:[{0}]' -f $relPath | Write-verbose

        # return the result here
        $relPath
    }
}

function LoadFileReplacer{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [string]$psbuildpath = ('C:\data\mycode\psbuild\OutputRoot\_psbuild-nuget\tools\psbuild.psd1')
    )
    process{
        # load psbuild
        $psbuildmod = (Get-Module -Name psbuild -ErrorAction SilentlyContinue)
        if($psbuildmod -ne $null){
            Import-Module $psbuildpath -Global -DisableNameChecking
        }

        Import-FileReplacer
    }
}


Load-NewtonsoftJson
LoadFileReplacer
#GetGuidsToReplace
#UpdateVsTemplateFiles


