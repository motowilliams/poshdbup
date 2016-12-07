Param(
    $databaseName = "Test",
    $databaseServer = ".\sqlexpress2014",
    $sqlScriptsRoot = "scripts",
    $migrationScriptsDirectory = "up",
    $testDataScriptsDirectory = "testdata",
    $versionTable = "version",
    [switch]$sampledata,
    $dbupVersion = "3.3.5",
    [switch]$EnsureDatabase,
    [switch]$DropDatabase
)

#optionally drop the target database
if ($DropDatabase) {
    Write-Host "Dropping database $DatabaseName" -ForegroundColor Red
    $sqlConnection = New-Object System.Data.SqlClient.SqlConnection;
    #note the database is Master
    $sqlConnection.ConnectionString = "server=$databaseServer;database=master;Trusted_Connection=Yes;"
    $sqlConnection.Open();
    $sqlCommand = New-Object System.Data.SqlClient.SqlCommand;
    $sqlCommand.Connection = $sqlConnection;
    $sqlCommand.CommandText = "IF EXISTS(select name from sys.databases where name='$DatabaseName') BEGIN ALTER DATABASE $DatabaseName SET SINGLE_USER WITH ROLLBACK IMMEDIATE;DROP DATABASE $DatabaseName;END";
    $result = $sqlCommand.ExecuteNonquery();
    $sqlConnection.Close();
}

#Download DbUp package if nessessary
$dbuppackage = "dbup.$dbupVersion.nupkg"
$dbupzip = "$PSScriptRoot\$dbuppackage.zip"
$dbupassembly = "dbup.dll"
$dbupassemblyPath = "$PSScriptRoot\$dbupassembly"
$dbupPackagedAssemblyPath = "$PSScriptRoot\$dbuppackage\lib\net35\$dbupassembly"
if(!(Test-Path -Path $dbupassemblyPath)){
    Write-Host "Downloading dbup library" -ForegroundColor Green
    $progressPreference = 'SilentlyContinue'
    (New-Object System.Net.WebClient).DownloadFile("https://api.nuget.org/packages/$dbuppackage", $dbupzip)
    $progressPreference = 'Continue'
    Expand-Archive $dbupzip -Force
    Remove-Item $dbupzip -Force
    Move-Item -Path $dbupPackagedAssemblyPath -Destination $dbupassemblyPath
    Remove-Item -Force -Recurse "$PSScriptRoot\$dbuppackage"
}
Add-Type -Path $dbupassemblyPath

$sqlScriptsRoot = Resolve-Path -Path $sqlScriptsRoot

$connectionString = "server=$databaseServer;database=$databaseName;Trusted_Connection=Yes;"

#optionally create the target database
if($EnsureDatabase){
# EnsureDatabase.For.SqlDatabase(connectionString);
Write-Host "Ensuring Database $databaseName exists" -ForegroundColor Green
$dbup = [DbUp.EnsureDatabase]::For
$dbup = [SqlServerExtensions]::SqlDatabase($dbUp, $connectionString)
}

Write-Host "Running $migrationScriptsDirectory scripts" -ForegroundColor Green
$dbUp = [DbUp.DeployChanges]::To
$dbUp = [SqlServerExtensions]::SqlDatabase($dbUp, $connectionString)
$dbUp = [StandardExtensions]::WithScriptsFromFileSystem($dbUp, "$sqlScriptsRoot\$migrationScriptsDirectory")
$dbUp = [SqlServerExtensions]::JournalToSqlTable($dbUp, 'dbo', 'version')
$dbUp = [StandardExtensions]::LogToConsole($dbUp)
$upgradeResult = $dbUp.Build().PerformUpgrade()

#optionally add sample data to the target database
if($sampledata){
    Write-Host "Running $testDataScriptsDirectory scripts" -ForegroundColor Green
    $dbUp = [StandardExtensions]::WithScriptsFromFileSystem($dbUp, "$sqlScriptsRoot\$testDataScriptsDirectory")
    $dbUp = [SqlServerExtensions]::JournalToSqlTable($dbUp, 'dbo', $versionTable)
    $dbUp = [StandardExtensions]::LogToConsole($dbUp)
    $upgradeResult = $dbUp.Build().PerformUpgrade()
}
