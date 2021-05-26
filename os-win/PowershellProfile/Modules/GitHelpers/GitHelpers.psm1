$Global:MyBranchPrCreation = @{}

function Show-UntrackedFiles
{
    git ls-files --others --exclude-standard
}

function Git-CreateBranch
{
    param([Parameter(ValueFromPipeline=$true)][string]$BranchName)
    if(![string]::IsNullOrEmpty($BranchName))
    {
        $BranchName = "dev/$env:USERNAME/$BranchName"
        $remoteBranch = "origin/" + $BranchName
        git cob $BranchName
        git push origin $BranchName
        git branch --set-upstream-to=$remoteBranch
    }
}

function Git-CreateFeatureBranch
{
    param([Parameter(ValueFromPipeline=$true)][string]$BranchName, [string]$Topic)
    if(![string]::IsNullOrEmpty($BranchName))
    {
        $BranchName = "feature/$BranchName/$Topic"
        $remoteBranch = "origin/" + $BranchName
        git cob $BranchName
        git push origin $BranchName
        git branch --set-upstream-to=$remoteBranch
    }
}

function Git-DeleteBranch
{
    param([Parameter(ValueFromPipeline=$true)][string]$BranchName)
    if([string]::IsNullOrEmpty($BranchName))
    {
       $status = Get-GitStatus
       $BranchName = $status.Branch
    }

    Git-AbandonCurrentPR

    $remoteBranch = ":" + $BranchName
    git checkout master
    git branch -D $BranchName
    git push origin $remoteBranch
}

function Git-Iterate
{
    param([Parameter(ValueFromPipeline=$true)][string]$Message, [switch] $DoNotReview = $false)

    $firstCommit = Git-FirstBranchCommitMessage

    if([string]::IsNullOrWhiteSpace($Message))
    {
        if(!$firstCommit)
        {
            Write-Error "First commit not found! Message is mandatory"
            return;
        }

        $Message = "Next iteration (addressing PR comments/fixes)"
    }
    
    git commit -am "$Message"
    git push
    
    $status = Get-GitStatus
    $localBranch = $status.Branch

    if(!$Global:MyBranchPrCreation.ContainsKey($localBranch))
    {
        $created = Git-IsPRCreated

        if(!$created)
        {
            $firstCommit = Git-FirstBranchCommitMessage        
            if($DoNotReview)
            {
                az repos pr create --auto-complete true --draft true --squash true --delete-source-branch true --open --title "[DoNotReview] $firstCommit" | Out-Null
            }
            else
            {
                az repos pr create --auto-complete true --squash true --delete-source-branch true --open --title "$firstCommit" --description "$firstCommit" | Out-Null
            }
        }
    
        $Global:MyBranchPrCreation.Add($localBranch, $true)
    }
}

function Git-FirstBranchCommitMessage
{
    $status = Get-GitStatus
    $localBranch = $status.Branch
    $data = git log --oneline --reverse master..$localBranch
    if($data -and $data.Count -gt 1)
    {
        return $data[0].Substring($data[0].IndexOf(" ")).Trim()
    }
    if($data -and $data.Count -eq 1)
    {
        return $data.Substring($data.IndexOf(" ")).Trim()
    }
    
    return $null;
}

function Git-Clean()
{
    git clean -xfd
}

function Git-CheckoutFolder
{
    param([Parameter(ValueFromPipeline=$true)][string]$Folder)
    if(!$Folder)
    {
        $Folder = ($pwd).Path
    }

    git co -- "$Folder"
}

function Git-IsPRCreated
{
    $status = Get-GitStatus
    $currentBranchName = $status.Branch
    $fullData = (az repos pr list --source-branch "$currentBranchName") | ConvertFrom-Json
    return ($fullData.Length -gt 0);
}

function Git-GetCurrentPR
{
    $status = Get-GitStatus
    $currentBranchName = $status.Branch
    $fullData = (az repos pr list --source-branch "$currentBranchName") | ConvertFrom-Json
    return $fullData
}

function Git-AbandonCurrentPR
{
    $status = Get-GitStatus
    $currentBranchName = $status.Branch

    $fullData = (az repos pr list --source-branch "$currentBranchName") | ConvertFrom-Json
    if($fullData.Length -eq 1)
    {
        $prId = $fullData[0].pullRequestId
        az repos pr update --id $prId --status abandoned | Out-Null
        $Global:MyBranchPrCreation.Remove($currentBranchName) | Out-Null
    }
    else
    {
        Write-Error "No active PR found for this source branch"
    }
}

function Git-OpenActivePR
{
    $status = Get-GitStatus
    $currentBranchName = $status.Branch
    $fullData = (az repos pr list --source-branch "$currentBranchName") | ConvertFrom-Json
    if($fullData.Length -eq 1)
    {
        $prId = $fullData[0].pullRequestId
        az repos pr show --id $prId --open | Out-Null
    }
    else
    {
        Write-Error "No active PR found for this source branch"
    }
}

function Git-PublishPR
{
    $status = Get-GitStatus
    $currentBranchName = $status.Branch
    $fullData = (az repos pr list --source-branch "$currentBranchName") | ConvertFrom-Json
    if($fullData.Length -eq 1)
    {
        $prId = $fullData[0].pullRequestId
        az repos pr update --id $prId --draft false | Out-Null
    }
    else
    {
        Write-Error "No active PR found for this source branch"
    }
}

function Git-UpdatePRTitle
{
    param([Parameter(Mandatory=$true)][string]$Title)
    $status = Get-GitStatus
    $currentBranchName = $status.Branch
    $fullData = (az repos pr list --source-branch "$currentBranchName") | ConvertFrom-Json
    if($fullData.Length -eq 1)
    {
        $prId = $fullData[0].pullRequestId
        az repos pr update --id $prId --title $Title | Out-Null
    }
    else
    {
        Write-Error "No active PR found for this source branch"
    }
}

function Git-UpdatePRDescription
{
    param([Parameter(Mandatory=$true)][string]$Description)
    $status = Get-GitStatus
    $currentBranchName = $status.Branch
    $fullData = (az repos pr list --source-branch "$currentBranchName") | ConvertFrom-Json
    if($fullData.Length -eq 1)
    {
        $prId = $fullData[0].pullRequestId
        az repos pr update --id $prId --description $Description | Out-Null
    }
    else
    {
        Write-Error "No active PR found for this source branch"
    }
}
