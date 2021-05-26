function Get-AzSwiftTeam
{
    return Get-MsGraphTeamUnder -emailId chanravi@microsoft.com -includeLeader;
}

function Get-AzBlazeTeam
{
    return Get-MsGraphTeamUnder -emailId mamadoukane@microsoft.com -includeLeader;
}

function Get-AzBlitzPPSTeam
{
    return Get-MsGraphTeamUnder -emailId daudhow@ntdev.microsoft.com -includeLeader;
}

function Get-CrpCoreTeam
{
    return Get-MsGraphTeamUnder -emailId smotwani@microsoft.com -includeLeader;
}

function Get-TeamActivePRReportTable
{
    param([Parameter(ValueFromPipeline=$true)][string[]]$emailAddresses)

    $tableRows = @()

    foreach($emailAddress in $emailAddresses)
    {
        $prs = (az repos pr list --organization https://msazure.visualstudio.com --project One --creator $emailAddress --status active) | ConvertFrom-Json
        
        foreach($pr in $prs)
        {
            if(!$pr.isDraft)
            {
                $prLink = "https://msazure.visualstudio.com/One/_git/" + $pr.repository.Name + "/pullrequest/" + $pr.pullRequestId
                $creationDate = [datetime]$pr.creationDate
                $diff = [datetime]::UtcNow.Subtract($creationDate)

                $row = [PSCustomObject]@{
                    ID = '<a href="' + $prLink + '">' + $pr.pullRequestId + '</a>'
                    Title = $pr.title
                    Repo = $pr.repository.name
                    Creator = '<a href="mailto:' + $emailAddress + '?subject=Regarding PR ' + $pr.pullRequestId +'">' + $pr.createdBy.displayName + '</a>'
                    OpenFor = $diff.Days
                }

                $tableRows += $row
            }
        }
    }

    $tableRows = $tableRows | sort -Property OpenFor -Descending

    $data = $tableRows | ConvertTo-Html -Fragment -As Table;
    return [System.Web.HttpUtility]::HtmlDecode($data);
}

function Get-TeamActivePRHealthReportTable
{
    param([Parameter(ValueFromPipeline=$true)][string[]]$emailAddresses)

    $tableRows = @()
    $excludeAuthors = [System.Collections.Generic.HashSet[String]] @("Microsoft.VisualStudio.Services.TFS", "CDP Ownership Enforcer", "CDP Buddy", "Azure Pipelines Test Service")


    $token = Get-AccessToken

    foreach($emailAddress in $emailAddresses)
    {
        $prs = (az repos pr list --organization https://msazure.visualstudio.com --project One --creator $emailAddress --status active) | ConvertFrom-Json
        
        foreach($pr in $prs)
        {
            if(!$pr.isDraft)
            {
                # Initialize paths and fetch information
                $commentators = [System.Collections.ArrayList]::new();
                $iterationUrl = $pr.url + "/iterations"
                $threadsUrl = $pr.url + "/threads"
                $mergeChangesUrl = $pr.lastMergeCommit.url + "/changes"

                $iterations = (az rest --method get --url $iterationUrl --headers "Authorization=Bearer $token" |ConvertFrom-Json)
                $iterations.value |% {$updatedDate = [datetime]$_.updatedDate;}

                $threads = (az rest --method get --url $threadsUrl --headers "Authorization=Bearer $token" |ConvertFrom-Json)
                $mergeChanges = (az rest --method get --url $mergeChangesUrl --headers "Authorization=Bearer $token" |ConvertFrom-Json)

                # Basic information about the PR
                $prLink = "https://msazure.visualstudio.com/One/_git/" + $pr.repository.Name + "/pullrequest/" + $pr.pullRequestId
                $creationDate = [datetime]$pr.creationDate
                $diff = [datetime]::UtcNow.Subtract($creationDate)
                $updatedDiff = [datetime]::UtcNow.Subtract($updatedDate)

                # We only care about text comments and comments coming from devs
                $devThreads = $threads.value |? {!$excludeAuthors.Contains($_.comments[0].author.displayName) -and $_.comments[0].commentType -eq "text"}
                $addressedThreads = $devThreads |? {$_.status -ne "active"};
                $pendingComments = $devThreads.Count - $addressedThreads.Count

                # Find the reviewers in the discussion - only the ones who have responded or commented as we do not want every owner
                $devThreads |% {$_.comments[0].author.displayName} | select -Unique |% {$commentators.Add($_)  | Out-Null;}
                
                foreach($prReviewer in $pr.reviewers)
                {
                    # We will skip groups and look into individuals or OE
                    if($prReviewer.displayName.Contains("[One]") -or $prReviewer.displayName.Contains("[TEAM FOUNDATION]"))
                    {
                        continue;
                    }

                    # We are interested in non-neutral reviews
                    if($prReviewer.vote -ne 0)
                    {
                        # TODO: Inefficient - unblock first
                        if($commentators.Contains($prReviewer.displayName))
                        {
                            $commentators.Remove($prReviewer.displayName) | Out-Null;
                        }

                        if($prReviewer.vote -lt 0)
                        {
                            $commentators.Add('<b><span style="color:brown;">' + $prReviewer.displayName + '</span></b>') | Out-Null;
                        }
                        if($prReviewer.vote -gt 0)
                        {
                            $commentators.Add('<b><span style="color:darkgreen;">' + $prReviewer.displayName + '</span></b>') | Out-Null;
                        }
                    }
                }

                # Moving to a PS array
                $commentators = $commentators |% {$_ + "<br/>"}
                if(!$commentators -or $commentators.Count -eq 0)
                {
                    $commentators = @("None")
                }

                # Figure out more details about the actual changes
                $fileChangeCount = 0
                foreach ($mergeChange in $mergeChanges)
                {
                    $fileChanges = $mergeChange.changes |? {!$_.item.isFolder}
                    $fileChangeCount = $fileChangeCount + $fileChanges.Count
                }

                # Colorize the file change count
                if($fileChangeCount -gt 0 -and $fileChangeCount -le 10)
                {
                    $fileChangeCount = '<span style="color:green;">' + $fileChangeCount + '</span>'
                }
                elseif($fileChangeCount -gt 10 -and $fileChangeCount -le 20)
                {
                    $fileChangeCount = '<span style="color:darkorange;">' + $fileChangeCount + '</span>'
                }
                elseif($fileChangeCount -gt 30)
                {
                    $fileChangeCount = '<b><span style="color:darkred;">' + $fileChangeCount + '</span></b>'
                }

                # We can do more with understanding the independent diffs
                # https://stackoverflow.com/questions/61827842/is-there-a-way-to-get-the-raw-diff-of-a-commit-via-the-azure-devops-api
                # https://stackoverflow.com/questions/41713616/lines-of-code-modified-in-each-commit-in-tfs-rest-api-how-do-i-get

                $row = [PSCustomObject]@{
                    PR = ('<a href="' + $prLink + '">' + $pr.title + '</a><br /><span style="font-size:9.0pt;">' + $iterations.count + ' iterations, ' + $pendingComments + ' pending comments</span><br /><span style="font-size:8.0pt;">Dev = ' + '<b><a href="mailto:' + $emailAddress + '?subject=Regarding PR ' + $pr.pullRequestId +'">' + $pr.createdBy.displayName + '</a></b></span>')
                    Reviewers = [string]::Join("", $commentators)
                    CreatedAgo = $diff.Days
                    UpdatedAgo = $updatedDiff.Days
                    CommentCount = $devThreads.Count
                    Addressed = $addressedThreads.Count
                    FileCount = $fileChangeCount
                }

                $tableRows += $row
            }
        }
    }

    $tableRows = $tableRows | sort -Property CreatedAgo -Descending

    $data = $tableRows | ConvertTo-Html -Fragment -As Table;
    return [System.Web.HttpUtility]::HtmlDecode($data);
}

function Get-TeamClosedPRReportTable
{
    param([Parameter(ValueFromPipeline=$true)][string[]]$emailAddresses)

    $tableRows = @()

    foreach($emailAddress in $emailAddresses)
    {
        $prs = (az repos pr list --organization https://msazure.visualstudio.com --project One --creator $emailAddress --status completed) | ConvertFrom-Json
        
        foreach($pr in $prs)
        {
            $prLink = "https://msazure.visualstudio.com/One/_git/" + $pr.repository.Name + "/pullrequest/" + $pr.pullRequestId
            $closedDate = [datetime]$pr.closedDate
            $diff = [datetime]::UtcNow.Subtract($closedDate)

            if($diff.Days -lt 14)
            {
                $row = [PSCustomObject]@{
                    ID = '<a href="' + $prLink + '">' + $pr.pullRequestId + '</a>'
                    Title = $pr.title
                    Repo = $pr.repository.name
                    Creator = '<a href="mailto:' + $emailAddress + '?subject=Regarding PR ' + $pr.pullRequestId +'">' + $pr.createdBy.displayName + '</a>'
                    ClosedOn = $closedDate
                }

                $tableRows += $row
            }
        }
    }

    $tableRows = $tableRows | sort -Property ClosedOn

    $data = $tableRows | ConvertTo-Html -Fragment -As Table;
    return [System.Web.HttpUtility]::HtmlDecode($data);
}

function Get-TeamPRBoard
{
    param([Parameter(ValueFromPipeline=$true)][string[]]$emailAddresses)

    $tableRows = @()

    foreach($emailAddress in $emailAddresses)
    {
        $completedCount = 0;
        $activeCount = 0;
        $dev = $emailAddress;
        
        $prs = (az repos pr list --organization https://msazure.visualstudio.com --project One --creator $emailAddress --status completed) | ConvertFrom-Json
        foreach($pr in $prs)
        {
            $prLink = "https://msazure.visualstudio.com/One/_git/" + $pr.repository.Name + "/pullrequest/" + $pr.pullRequestId
            $closedDate = [datetime]$pr.closedDate
            $diff = [datetime]::UtcNow.Subtract($closedDate)

            if($diff.Days -lt 14)
            {
                $completedCount = $completedCount+1;
            }

            if($dev -eq $emailAddress)
            {
                $dev = $pr.createdBy.displayName
            }
        }

        $prs = (az repos pr list --organization https://msazure.visualstudio.com --project One --creator $emailAddress --status active) | ConvertFrom-Json
        foreach($pr in $prs)
        {
            if(!$pr.isDraft)
            {
                $activeCount = $activeCount + 1
            }

            if($dev -eq $emailAddress)
            {
                $dev = $pr.createdBy.displayName
            }
        }

        $row = [PSCustomObject]@{
                    Developer = $dev
                    Active = $activeCount
                    Closed = $completedCount
                    Total = $activeCount + $completedCount
                }
        
        $tableRows += $row
    }

    $tableRows = $tableRows | sort -Property Total -Descending
    $data = $tableRows | ConvertTo-Html -Fragment -As Table;
    return [System.Web.HttpUtility]::HtmlDecode($data);
}

function Get-FeatureStatusReportTable
{
    param([Parameter(ValueFromPipeline=$true)][string]$queryId)

    $token = Get-AccessToken
    $tableRows = @()
    $features = az boards query --id $queryId --organization https://msazure.visualstudio.com/ --project One | ConvertFrom-Json
    # 18605e01-0427-4f60-829c-29f5a71a7865

    foreach($feature in $features)
    {
        $item = az boards work-item show --id $feature.id --organization https://msazure.visualstudio.com/ | ConvertFrom-Json
        $itemLink = "https://msazure.visualstudio.com/One/_workitems/edit/" + $item.id

        $title = $feature.fields.'System.Title'
        if($feature.fields.'One_custom.CustomField3')
        {
            $title = $feature.fields.'One_custom.CustomField3'
        }
        $title = $title.Replace("Title = ", "")

        $devs = $feature.fields.'One_custom.CustomField2'
        $devs = $devs.Replace("Developers = ", "")

        $pms = $feature.fields.'One_custom.CustomField1'
        $pms = $pms.Replace("PM = ", "")

        $commentUrl = $item.url +"/comments"
        $comment = "";
        
        $commentData = (az rest --method get --url $commentUrl --headers "Authorization=Bearer $token" |ConvertFrom-Json)

        if($commentData -and $commentData.comments)
        {
            $comment = $commentData.comments[0].Text
            $modifiedDate = $commentData.comments[0].modifiedDate
            $comment = $comment + '<p style="margin:0in 0in 8pt;font-size:11pt;font-family:Calibri, sans-serif;"><span style="font-size:7.0pt;font-family:&quot;Segoe UI&quot;,sans-serif;color:#7F7F7F;background:white;">Last modified on ' + $modifiedDate + '</span><span style="font-size:7.0pt;color:#7F7F7F;"></span></p></span><span style="font-size:7.0pt;"></span></p>'
        }

        $crew = '<div style="margin:0px 0in;font-size:14pt;"><h1 style="margin:0in;font-size:13.0pt;color:#1E4E79;">' + $title + '</h1><h5 style="margin:0in;font-size:10.0pt;color:#2E75B5;">Devs: ' + $devs + '</h5><h5 style="margin:0in;font-size:10.0pt;color:#2E75B5;">PM: ' + $pms + '</h5><p style="margin:0in;font-size:6.0pt;color:#2E75B5;"><a href="' + $itemLink + '">Backlog ' + $item.id + '</a></p><br></div>'

        $row = [PSCustomObject]@{
            'Feature & Crew' = $crew
            'Design & Milestones' = $item.fields.'System.Description'
            Status = $comment
        }

        $tableRows += $row
    }

    $data = $tableRows | ConvertTo-Html -Fragment -As Table;
    return [System.Web.HttpUtility]::HtmlDecode($data);
}

function Get-TableStyle
{
    return "
   <style>
        TABLE {
            border-width: 1px;
            border-style: solid;
            border-color: black;
            border-collapse: collapse;
            background-color: white;
        }

        TH {
            border-width: 1px;
            padding: 3px;
            border-style: solid;
            border-color: black;
            background-color: #001e5a;
            text-align: left;
        }

        TD {
            border-width: 1px;
            padding: 3px;
            border-style: solid;
            border-color: black;
        }

        tr:nth-child(odd) {
            background: #ffffff;
        }
        
        tr:nth-child(even){
            background: #fffcfd;
        }
    </style>";
}

function Get-AzSwiftEmailIntro
{
    return '
    <div>
        <p>Status report for AzSwift team - for detailed drill down look at <a href="https://msazure.visualstudio.com/One/_backlogs/backlog/AzSwift/Epics">Epics</a>. Current sprint details <a href="https://msazure.visualstudio.com/One/_sprints/taskboard/AzSwift/One/Azure%20Compute/CPlat/Cobalt/">are here</a>.</p>
    </div>
    <h2>Feature status</h2>';
}

function Get-AzBlazeEmailIntro
{
    # TODO for AzBlaze - AzBlaze needs an area path and sprint board - until then use AzSwift. When done, update links.
    return '
    <div>
        <p>Status report for AzBlaze team - for detailed drill down look at <a href="https://msazure.visualstudio.com/One/_backlogs/backlog/AzSwift/Epics">Epics</a>. Current sprint details <a href="https://msazure.visualstudio.com/One/_sprints/taskboard/AzSwift/One/Azure%20Compute/CPlat/Cobalt/">are here</a>.</p>
    </div>
    <h2>Feature status</h2>';
}

function Get-AccessToken
{
    $tokenPayload = az account get-access-token | ConvertFrom-Json
    $token = $tokenPayload.accessToken
    return $token
}

function Get-MsGraphAccessToken
{
    $tokenPayload = az account get-access-token --resource-type ms-graph | ConvertFrom-Json
    $token = $tokenPayload.accessToken
    return $token
}

function Get-OrgChart
{
    param([Parameter(ValueFromPipeline=$true)][string]$id)
    $token = Get-MsGraphAccessToken
    return (az rest --method get --url "https://graph.microsoft.com/v1.0/users/$id/directReports" --headers "Authorization=Bearer $token" | ConvertFrom-Json)
}

function Get-MsGraphUserDetailsByEmail
{
    param([Parameter(ValueFromPipeline=$true)][string]$emailId)

    $token = Get-MsGraphAccessToken
    return (az rest --method get --url "https://graph.microsoft.com/v1.0/users/$emailId" --headers "Authorization=Bearer $token" | ConvertFrom-Json)    
}

function Get-MsGraphTeamUnder
{
    param([Parameter(ValueFromPipeline=$true)][string]$emailId, [switch] $includeLeader = $false, [switch]$recurse = $false)

    $out = @()
    
    if($includeLeader)
    {
        $leader = Get-MsGraphUserDetailsByEmail -emailId $emailId
        $out += [PSCustomObject]@{
                        Id = $leader.id
                        Name = $leader.displayName
                        Email = $leader.userPrincipalName
                    }
    }

    $data = (Get-OrgChart -id $leader.id).value
    $data |% {$out += [PSCustomObject]@{
                    Id = $_.id
                    Name = $_.displayName
                    Email = $_.userPrincipalName
                }}

    if($recurse)
    {
        $data |% {$val = Get-MsGraphTeamUnder -emailId $_.userPrincipalName -recurse; foreach($i in $val) {$out += $i; }}
    }

    return $out;
}

function Send-AzSwiftDailyPRReport
{
    $style = Get-TableStyle
    $pr = Get-TeamActivePRHealthReportTable -emailAddresses (Get-AzSwiftTeam).Email

    $body = $style + "<h2>Active PRs</h2>" + $pr

    $from = $env:USERNAME + "@microsoft.com"
    Send-MailMessage -From $from -To "azswift@microsoft.com" -Subject 'AzSwift - PR Daily Report' -Body $body -BodyAsHtml -SmtpServer  "smtphost.redmond.corp.microsoft.com"
}

function Send-AzBlazeDailyPRReport
{
    $style = Get-TableStyle
    $pr = Get-TeamActivePRHealthReportTable -emailAddresses (Get-AzBlazeTeam).Email

    $body = $style + "<h2>Active PRs</h2>" + $pr

    $from = $env:USERNAME + "@microsoft.com"
    Send-MailMessage -From $from -To "azblaze-atl@microsoft.com" -Subject 'AzBlaze - PR Daily Report' -Body $body -BodyAsHtml -SmtpServer  "smtphost.redmond.corp.microsoft.com"
}

function Send-AzBlitzPPSDailyPRReport
{
    $style = Get-TableStyle
    $pr = Get-TeamActivePRHealthReportTable -emailAddresses (Get-AzBlitzPPSTeam).Email

    $body = $style + "<h2>Active PRs</h2>" + $pr

    $from = $env:USERNAME + "@microsoft.com"
    Send-MailMessage -From $from -To "chanravi@microsoft.com","sushantr@microsoft.com" -Subject 'AzBlitz PPS - PR Daily Report' -Body $body -BodyAsHtml -SmtpServer  "smtphost.redmond.corp.microsoft.com"
}

function Send-CrpCoreDailyPRReport
{
    $style = Get-TableStyle
    $pr = Get-TeamActivePRHealthReportTable -emailAddresses (Get-CrpCoreTeam).Email

    $body = $style + "<h2>Active PRs</h2>" + $pr

    $from = $env:USERNAME + "@microsoft.com"
    Send-MailMessage -From $from -To "chanravi@microsoft.com","sushantr@microsoft.com" -Subject 'CRP Core - PR Daily Report' -Body $body -BodyAsHtml -SmtpServer  "smtphost.redmond.corp.microsoft.com"
}

function Send-AzSwiftExecutiveTeamStatus
{
    $feature = Get-FeatureStatusReportTable -queryId 18605e01-0427-4f60-829c-29f5a71a7865
    $pr = Get-TeamActivePRReportTable -emailAddresses (Get-AzSwiftTeam).Email
    $closedPR = Get-TeamClosedPRReportTable -emailAddresses (Get-AzSwiftTeam).Email
    $prBoard = Get-TeamPRBoard -emailAddresses (Get-AzSwiftTeam).Email
    $intro = Get-AzSwiftEmailIntro

    $style = Get-TableStyle

    $body = $style + $intro + $feature + "<h2>Active PRs</h2>" + $pr + "<h2>Closed PRs</h2>" + $closedPR + "<h2>PR Board</h2>" + $prBoard

    $from = $env:USERNAME + "@microsoft.com"

    Send-MailMessage -From $from -To "YunusM-EngLeads@microsoft.com" -Cc "azswift@microsoft.com","sushantr@microsoft.com" -Subject 'AzSwift Weekly Report' -Body $body -BodyAsHtml -SmtpServer  "smtphost.redmond.corp.microsoft.com"
    # Send-MailMessage -From $from -To "chanravi@microsoft.com" -Subject 'AzSwift Weekly Report' -Body $body -BodyAsHtml -SmtpServer  "smtphost.redmond.corp.microsoft.com"
}

function Send-AzSwiftStageExecutiveTeamStatus
{
    $feature = Get-FeatureStatusReportTable -queryId 18605e01-0427-4f60-829c-29f5a71a7865
    $pr = Get-TeamActivePRReportTable -emailAddresses (Get-AzSwiftTeam).Email
    $closedPR = Get-TeamClosedPRReportTable -emailAddresses (Get-AzSwiftTeam).Email
    $prBoard = Get-TeamPRBoard -emailAddresses (Get-AzSwiftTeam).Email
    $intro = Get-AzSwiftEmailIntro
    
    $style = Get-TableStyle

    $body = $style + $intro + $feature + "<h2>Active PRs</h2>" + $pr + "<h2>Closed PRs</h2>" + $closedPR + "<h2>PR Board</h2>" + $prBoard

    $from = $env:USERNAME + "@microsoft.com"

    Send-MailMessage -From $from -To "azswift@microsoft.com" -Subject 'AzSwift Weekly Report (Stage) - Please update before 11:00AM' -Body $body -BodyAsHtml -SmtpServer  "smtphost.redmond.corp.microsoft.com"
    #Send-MailMessage -From $from -To "chanravi@microsoft.com" -Subject 'AzSwift Weekly Report (Stage) - Please update before 11:00AM' -Body $body -BodyAsHtml -SmtpServer  "smtphost.redmond.corp.microsoft.com"
}

function Send-AzBlazeExecutiveTeamStatus
{
    $feature = Get-FeatureStatusReportTable -queryId e775d558-7a29-43e2-a5d1-5408dc8dc62f
    $pr = Get-TeamActivePRReportTable -emailAddresses (Get-AzBlazeTeam).Email
    $closedPR = Get-TeamClosedPRReportTable -emailAddresses (Get-AzBlazeTeam).Email
    $prBoard = Get-TeamPRBoard -emailAddresses (Get-AzBlazeTeam).Email
    $intro = Get-AzBlazeEmailIntro

    $style = Get-TableStyle

    $body = $style + $intro + $feature + "<h2>Active PRs</h2>" + $pr + "<h2>Closed PRs</h2>" + $closedPR + "<h2>PR Board</h2>" + $prBoard

    $from = $env:USERNAME + "@microsoft.com"

    Send-MailMessage -From $from -To "YunusM-EngLeads@microsoft.com" -Cc "azblaze-atl@microsoft.com","sushantr@microsoft.com" -Subject 'AzBlaze Weekly Report' -Body $body -BodyAsHtml -SmtpServer  "smtphost.redmond.corp.microsoft.com"
    # Send-MailMessage -From $from -To "jowherry@microsoft.com" -Subject 'AzBlaze Weekly Report' -Body $body -BodyAsHtml -SmtpServer  "smtphost.redmond.corp.microsoft.com"
}

function Send-AzBlazeStageExecutiveTeamStatus
{
    $feature = Get-FeatureStatusReportTable -queryId e775d558-7a29-43e2-a5d1-5408dc8dc62f
    $pr = Get-TeamActivePRReportTable -emailAddresses (Get-AzBlazeTeam).Email
    $closedPR = Get-TeamClosedPRReportTable -emailAddresses (Get-AzBlazeTeam).Email
    $prBoard = Get-TeamPRBoard -emailAddresses (Get-AzBlazeTeam).Email
    $intro = Get-AzBlazeEmailIntro
    
    $style = Get-TableStyle

    $body = $style + $intro + $feature + "<h2>Active PRs</h2>" + $pr + "<h2>Closed PRs</h2>" + $closedPR + "<h2>PR Board</h2>" + $prBoard

    $from = $env:USERNAME + "@microsoft.com"

    Send-MailMessage -From $from -To "azblaze-atl@microsoft.com" -Subject 'AzBlaze Weekly Report (Stage) - Please update before 11:00AM ET' -Body $body -BodyAsHtml -SmtpServer  "smtphost.redmond.corp.microsoft.com"
    #Send-MailMessage -From $from -To "jowherry@microsoft.com" -Subject 'AzBlaze Weekly Report (Stage) - Please update before 11:00AM ET' -Body $body -BodyAsHtml -SmtpServer  "smtphost.redmond.corp.microsoft.com"
}

function Send-SushantsTeamDailyPRReport
{
    Send-AzBlitzPPSDailyPRReport
    Send-AzBlazeDailyPRReport
    Send-AzSwiftDailyPRReport
    Send-CrpCoreDailyPRReport
}