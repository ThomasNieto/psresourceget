﻿# Copyright (c) Thomas Nieto - All Rights Reserved
# You may use, distribute and modify this code under the
# terms of the MIT license.

using module AnyPackage
using module Microsoft.PowerShell.PSResourceGet

using namespace System.Collections.Generic
using namespace System.Threading
using namespace AnyPackage.Provider
using namespace AnyPackage.Feedback
using namespace Microsoft.PowerShell.PSResourceGet.UtilClasses

[PackageProvider('PSResourceGet')]
class PSResourceGetProvider : PackageProvider, IGetPackage, IFindPackage,
IInstallPackage, ISavePackage, IUninstallPackage,
IUpdatePackage, IPublishPackage, IGetSource, ISetSource, ICommandNotFound {
    [PackageProviderInfo] Initialize([PackageProviderInfo] $providerInfo) {
        return [PSResourceGetProviderInfo]::new($providerInfo)
    }

    [IEnumerable[CommandNotFoundFeedback]] FindPackage([CommandNotFoundContext] $context, [CancellationToken] $token) {
        $dict = [Dictionary[string, CommandNotFoundFeedback]]::new([StringComparer]::OrdinalIgnoreCase)
        $packages = $this.ProviderInfo.CommandCache[$context.Command]

        foreach ($package in $packages) {
            if (!$dict.ContainsKey($package.Name)) {
                $feedback = [CommandNotFoundFeedback]::new($package.Name, $this.ProviderInfo)
                $dict.Add($package.Name, $feedback)
            }
        }

        return $dict.Values
    }

    #region GetPackage
    [void] GetPackage([PackageRequest] $request) {
        $params = @{
            Name        = $request.Name
            ErrorAction = 'SilentlyContinue'
        }

        if ($request.Version) {
            $params['Version'] = $request.Version
        }

        $request.DynamicParameters |
        ConvertTo-Hashtable -Hashtable $params -IsBound

        Get-InstalledPSResource @params |
        Write-Package -Request $request
    }
    #endregion

    #region FindPackage
    [void] FindPackage([PackageRequest] $request) {
        $params = @{
            Name        = $request.Name
            Prerelease  = $request.Prerelease
            ErrorAction = 'SilentlyContinue'
        }

        if ($request.Version) {
            $params['Version'] = $request.Version
        }

        if ($request.Source) {
            $params['Repository'] = $request.Source
        }

        $request.DynamicParameters |
        ConvertTo-Hashtable -Hashtable $params -Exclude 'Latest' -IsBound

        $resources = Find-PSResource @params

        if ($request.DynamicParameters.Latest) {
            $resources = $resources | Get-Latest
        }

        $resources | Write-Package -Request $request
    }
    #endregion

    #region InstallPackage
    [void] InstallPackage([PackageRequest] $request) {
        $params = @{
            Name        = $request.Name
            Prerelease  = $request.Prerelease
            ErrorAction = 'SilentlyContinue'
        }

        if ($request.Version) {
            $params['Version'] = $request.Version
        }

        if ($request.Source) {
            $params['Repository'] = $request.Source
        }

        $installParams = @{ }

        $request.DynamicParameters |
        ConvertTo-Hashtable -Hashtable $installParams -IsBound

        Find-PSResource @params |
        Get-Latest |
        Install-PSResource @installParams -TrustRepository -PassThru |
        Write-Package -Request $request
    }
    #endregion

    #region SavePackage
    [void] SavePackage([PackageRequest] $request) {
        $params = @{
            Name        = $request.Name
            Prerelease  = $request.Prerelease
            ErrorAction = 'SilentlyContinue'
        }

        if ($request.Version) {
            $params['Version'] = $request.Version
        }

        if ($request.Source) {
            $params['Repository'] = $request.Source
        }

        $saveParams = @{ }

        $request.DynamicParameters |
        ConvertTo-Hashtable -Hashtable $saveParams -IsBound

        Find-PSResource @params |
        Get-Latest |
        Save-PSResource @saveParams -Path $request.Path -TrustRepository -PassThru |
        Write-Package -Request $request
    }
    #endregion

    #region UninstallPackage
    [void] UninstallPackage([PackageRequest] $request) {
        $params = @{
            Name        = $request.Name
            ErrorAction = 'SilentlyContinue'
        }

        if ($request.Version) {
            $params['Version'] = $request.Version
        }

        $uninstallParams = @{ }

        $request.DynamicParameters |
        ConvertTo-Hashtable -Hashtable $uninstallParams -IsBound

        # Issue to get PassThru parameter added
        # https://github.com/PowerShell/PSResourceGet/issues/667

        # Prerelease parameter causes it to silently fail
        # https://github.com/PowerShell/PSResourceGet/issues/842
        Get-InstalledPSResource @params |
        ForEach-Object {
            try {
                $_ | Uninstall-PSResource @uninstallParams -ErrorAction Stop
                $_ | Write-Package -Request $request
            }
            catch {
                $_
            }
        }
    }
    #endregion

    #region UpdatePackage
    [void] UpdatePackage([PackageRequest] $request) {
        $params = @{
            Prerelease  = $request.Prerelease
        }

        if ($request.Version) {
            $params['Version'] = $request.Version
        }

        if ($request.Source) {
            $params['Repository'] = $request.Source
        }

        $updateParams = @{ }

        $request.DynamicParameters |
        ConvertTo-Hashtable -Hashtable $updateParams -IsBound

        # Find-PSResource pipeline input
        # https://github.com/PowerShell/PSResourceGet/issues/666
        Get-InstalledPSResource -Name $request.Name -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Name -Unique |
        Find-PSResource @params -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Name -Unique |
        Update-PSResource @params @updateParams -TrustRepository -PassThru |
        Write-Package -Request $request
    }
    #endregion

    #region PublishPackage
    [void] PublishPackage([PackageRequest] $request) {
        $params = @{
            Path = $request.Path
        }

        if ($request.Source) {
            $params['Repository'] = $request.Source
        }

        $request.DynamicParameters |
        ConvertTo-Hashtable -Hashtable $params -IsBound

        try {
            # PassThru parameter
            # https://github.com/PowerShell/PSResourceGet/issues/718
            Publish-PSResource @params -ErrorAction Stop

            $params.Remove('Path')
            $params['Name'] = Get-Item -Path $request.Path |
            Select-Object -ExpandProperty BaseName

            Find-PSResource @params |
            Get-Latest |
            Write-Package -Request $request
        }
        catch {
            throw $_
        }
    }
    #endregion

    #region Source
    [void] GetSource([SourceRequest] $sourceRequest) {
        Get-PSResourceRepository -Name $sourceRequest.Name |
        Write-Source -SourceRequest $sourceRequest
    }

    [void] SetSource([SourceRequest] $sourceRequest) {
        $params = @{
            PassThru = $true
        }

        if ($sourceRequest.Location) {
            $params.Uri = $sourceRequest.Location
        }

        if ($null -ne $sourceRequest.Trusted) {
            $params.Trusted = $sourceRequest.Trusted
        }

        $sourceRequest.DynamicParameters |
        ConvertTo-Hashtable -Hashtable $params -IsBound

        Get-PSResourceRepository -Name $sourceRequest.Name |
        Set-PSResourceRepository @params |
        Write-Source -SourceRequest $sourceRequest
    }

    [void] RegisterSource([SourceRequest] $sourceRequest) {
        $params = @{
            Trusted  = $sourceRequest.Trusted
            PassThru = $true
        }

        if ($sourceRequest.DynamicParameters.PSGallery) {
            $params['PSGallery'] = $true
        }
        else {
            $params['Name'] = $sourceRequest.Name
            $params['Uri'] = $sourceRequest.Location
        }

        $sourceRequest.DynamicParameters |
        ConvertTo-Hashtable -Hashtable $params -Exclude 'PSGallery' -IsBound

        Register-PSResourceRepository @params |
        Write-Source -SourceRequest $sourceRequest
    }

    [void] UnregisterSource([SourceRequest] $sourceRequest) {
        Get-PSResourceRepository -Name $sourceRequest.Name |
        Unregister-PSResourceRepository -PassThru |
        Write-Source -SourceRequest $sourceRequest
    }
    #endregion

    [object] GetDynamicParameters([string] $commandName) {
        return $(switch ($commandName) {
            'Get-Package' { return [GetPackageDynamicParameters]::new() }
            'Find-Package' { return [FindPackageDynamicParameters]::new() }
            'Install-Package' { return [InstallPackageDynamicParameters]::new() }
            'Publish-Package' { return [PublishPackageDynamicParameters]::new() }
            'Save-Package' { return [SavePackageDynamicParameters]::new() }
            'Uninstall-Package' { return [UninstallPackageDynamicParameters]::new() }
            'Update-Package' { return [UpdatePackageDynamicParameters]::new() }
            'Set-PackageSource' { return [SetPackageSourceDynamicParameters]::new() }
            'Register-PackageSource' { return [RegisterPackageSourceDynamicParameters]::new() }
            default { return $null }
        })
    }
}

class PSResourceGetProviderInfo : PackageProviderInfo {
    [Dictionary[string, List[PSResourceInfo]]] $CommandCache = [Dictionary[string, List[PSResourceInfo]]]::new([StringComparer]::OrdinalIgnoreCase)
    
    PSResourceGetProviderInfo([PackageProviderInfo] $providerInfo) : base($providerInfo) {
        if ([Runspace]::DefaultRunspace.Name -eq $this.FullName) {
            $this.SetCommandCache()
        }
    }

    [void] SetCommandCache() {
        $packages = Find-PSResource -Name * -Type Module

        foreach ($package in $packages) {
            $commands = $package.Tags | Where-Object { $_ -like "PSCommand*" } | ForEach-Object { $_ -replace 'PSCommand_', '' }

            foreach ($command in $commands) {
                if ($this.CommandCache.ContainsKey($command)) {
                    $this.CommandCache[$command] += $package
                } else {
                    $list = [List[PSResourceInfo]]::new()
                    $list += $package
                    $this.CommandCache.Add($command, $package)
                }
            }
        }
    }
}

class GetPackageDynamicParameters {
    [Parameter()]
    [string] $Path

    [Parameter()]
    [ScopeType] $Scope
}

class FindPackageDynamicParameters {
    [Parameter()]
    [switch] $Credential

    [Parameter()]
    [string[]] $Tag

    [Parameter()]
    [ResourceType] $Type

    [Parameter()]
    [switch] $Latest

    [Parameter()]
    [switch] $IncludeDependencies
}

class PublishPackageDynamicParameters {
    [Parameter()]
    [string] $ApiKey

    [Parameter()]
    [switch] $Credential

    [Parameter()]
    [string] $DestinationPath

    [Parameter()]
    [switch] $SkipDependenciesCheck

    [Parameter()]
    [switch] $SkipModuleManifestValidate

    [Parameter()]
    [uri] $Proxy

    [Parameter()]
    [pscredential] $ProxyCredential
}

class InstallDynamicParameters {
    [Parameter()]
    [switch] $AuthenticodeCheck

    [Parameter()]
    [switch] $Credential

    [Parameter()]
    [switch] $SkipDependencyCheck

    [Parameter()]
    [string] $TemporaryPath
}

class InstallUpdateDynamicParameters : InstallDynamicParameters {
    [Parameter()]
    [switch] $AcceptLicense

    [Parameter()]
    [ScopeType] $Scope
}

class InstallPackageDynamicParameters : InstallUpdateDynamicParameters {
    [Parameter()]
    [switch] $Reinstall

    # Install-PSResource -NoClobber fails
    # https://github.com/PowerShell/PSResourceGet/issues/946
    # [Parameter()]
    # [switch] $NoClobber
}

class SavePackageDynamicParameters : InstallDynamicParameters {
    # Pipeline input fails with -AsNupkg
    # https://github.com/PowerShell/PSResourceGet/issues/948
    # [Parameter()]
    # [switch] $AsNupkg

    # Pipeline input fails with -IncludeXml
    # https://github.com/PowerShell/PSResourceGet/issues/949
    # [Parameter()]
    # [switch] $IncludeXml
}

class UninstallPackageDynamicParameters {
    [Parameter()]
    [switch] $SkipDependencyCheck

    [Parameter()]
    [ScopeType] $Scope
}

class UpdatePackageDynamicParameters : InstallUpdateDynamicParameters {
    [Parameter()]
    [switch] $Force
}

class SetPackageSourceDynamicParameters {
    [Parameter()]
    [int] $Priority

    [Parameter()]
    [PSCredentialInfo] $CredentialInfo
}

class RegisterPackageSourceDynamicParameters : SetPackageSourceDynamicParameters {
    [Parameter(ParameterSetName = 'PSGallery')]
    [switch] $PSGallery
}

[guid] $id = 'c9a39544-274b-4935-9cad-7423e8c47e6b'
[PackageProviderManager]::RegisterProvider($id, [PSResourceGetProvider], $MyInvocation.MyCommand.ScriptBlock.Module)

$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    [PackageProviderManager]::UnregisterProvider($id)
}

function ConvertTo-Hashtable {
    [CmdletBinding()]
    [OutputType([hashtable])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    param (
        [Parameter(Position = 0,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName)]
        [object]
        $InputObject,

        [Parameter()]
        [hashtable]
        $Hashtable = @{ },

        [Parameter()]
        [string[]]
        $Exclude,

        [Parameter()]
        [switch]
        $IsBound
    )

    process {
        if ($null -eq $InputObject) {
            return
        }

        $properties = $InputObject |
            Get-Member -MemberType Properties |
            Where-Object Name -notin $Exclude |
            Select-Object -ExpandProperty Name

        foreach ($property in $properties) {
            if ($IsBound -and -not $InputObject.$property) {
                continue
            }

            $Hashtable[$property] = $InputObject.$property
        }

        $Hashtable
    }
}

function Get-Latest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,
            ValueFromPipeline)]
        [PSResourceInfo]
        $Resource
    )

    begin {
        $resources = [List[PSResourceInfo]]::new()
    }

    process {
        $resources.Add($resource)
    }

    end {
        $resources |
        Group-Object -Property Name |
        ForEach-Object {
            # PSResourceGet returns the latest as the first object
            $_.Group | Select-Object -First 1
        }
    }
}

function Write-Source {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline)]
        [PSRepositoryInfo]
        $Source,

        [Parameter(Mandatory)]
        [SourceRequest]
        $SourceRequest
    )

    process {
        $sourceInfo = [PackageSourceInfo]::new($Source.Name,
                                           $Source.Uri,
                                           [bool]::Parse($Source.Trusted),
                                           @{ Priority = $Source.Priority
                                              CredentialInfo = $Source.CredentialInfo },
                                            $SourceRequest.ProviderInfo)
        $SourceRequest.WriteSource($sourceInfo)
    }
}

function Write-Package {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline)]
        [PSResourceInfo]
        $Resource,

        [Parameter(Mandatory)]
        [PackageRequest]
        $Request
    )

    begin {
        $sources = Get-PackageSource -Provider AnyPackage.PSResourceGet\PSResourceGet
    }

    process {
        $ht = ConvertTo-Hashtable $resource

        $deps = [List[PackageDependency]]::new()
        foreach ($dep in $resource.Dependencies) {
            $versionRange = [PackageVersionRange]::new($dep.VersionRange, $true)
            $dependency = [PackageDependency]::new($dep.Name, $versionRange)
            $deps.Add($dependency)
        }

        $source = $sources |
        Where-Object Name -eq $resource.Repository

        # Blank RepositorySourceLocation
        # https://github.com/PowerShell/PSResourceGet/issues/1052
        if (-not $source -and $resource.RepositorySourceLocation) {
            $source = [PackageSourceInfo]::new($resource.Repository, $resource.RepositorySourceLocation, $false, $Request.ProviderInfo)
        }

        if ($resource.Prerelease) {
            $version = "{0}-{1}" -f $resource.Version, $resource.Prerelease
        }
        else {
            $version = $resource.Version
        }

        $package = [PackageInfo]::new($resource.Name, $version, $source, $resource.Description, $deps, $ht, $Request.ProviderInfo)
        $Request.WritePackage($package)
    }
}
