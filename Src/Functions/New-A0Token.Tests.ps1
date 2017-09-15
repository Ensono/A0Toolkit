$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut"


# // START test setup //

$malformedURL = "http:/url.com"
$formedURL = "http://url.com"

$testExceptionMessage = "test exception"

$testClientId = "testClientId"
$testClientSecret = "testClientSecret"

. "$here\Private\New-ExceptionDetail.ps1"

# // END test setup //



Describe "New-A0Token" {

    Mock -CommandName Invoke-WebRequest -Verifiable -MockWith {@{}}

    Mock -CommandName New-ExceptionDetail
    
    Context "Parameter validation fails" {        

        It "should validate malformed URL and throw" {

            {New-A0Token -baseURL $malformedURL -clientId $testClientId -clientSecret $testClientSecret } | Should Throw

            Assert-MockCalled -CommandName Invoke-WebRequest -Exactly -Times 0
            Assert-MockCalled -CommandName New-ExceptionDetail -Exactly -Times 0
        }

        It "should validate clientId missing and throw" {

            {New-A0Token -baseURL $formedURL -clientId -clientSecret $testClientSecret } | Should Throw

            Assert-MockCalled -CommandName Invoke-WebRequest -Exactly -Times 0
            Assert-MockCalled -CommandName New-ExceptionDetail -Exactly -Times 0
        }

        It "should validate clientSecret missing and throw" {

            {New-A0Token -baseURL $formedURL -clientId $testClientId -clientSecret } | Should Throw

            Assert-MockCalled -CommandName Invoke-WebRequest -Exactly -Times 0
            Assert-MockCalled -CommandName New-ExceptionDetail -Exactly -Times 0
        }

        It "should validate grantType is correct value of 'client_credentials' and throw" {

            {New-A0Token -baseURL $formedURL -clientId $testClientId -clientSecret $testClientSecret -grantType xx } | Should Throw

            Assert-MockCalled -CommandName Invoke-WebRequest -Exactly -Times 0
            Assert-MockCalled -CommandName New-ExceptionDetail -Exactly -Times 0
        }


    }

    Context "Call Auth0" {

        It "should Invoke-WebRequest and return response" {

            New-A0Token -baseURL $formedURL -clientId $testClientId -clientSecret $testClientSecret | Should not be $null

            Assert-VerifiableMocks
        }

    }

    Context "Call Auth0 and fail" {

        Mock -CommandName Invoke-WebRequest -Verifiable -MockWith {
        
            Throw
        }

        It "should throw exception" {

            {New-A0Token -baseURL $formedURL -clientId $testClientId -clientSecret $testClientSecret} | Should Throw

        }

        Assert-VerifiableMocks
        Assert-MockCalled -CommandName New-ExceptionDetail -Exactly -Times 1


    }
}
