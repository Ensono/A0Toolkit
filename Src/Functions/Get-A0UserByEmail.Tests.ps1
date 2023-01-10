$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut"


# // START test setup //

$malformedURL = "http:/url.com"
$formedURL = "http://url.com"

$testExceptionMessage = "test exception"

$testEmail = "test.test@test.com"

. "$here\Private\New-ExceptionDetail.ps1"

# // END test setup //



Describe "Get-A0UserByEmail" {

    Mock -CommandName Invoke-WebRequest -Verifiable -MockWith {@{}}

    Mock -CommandName New-ExceptionDetail
    
    Context "Parameter validation fails" {        

        It "should validate malformed URL and throw" {

            {Get-A0UserByEmail -baseURL $malformedURL -email $testEmail } | Should Throw

            Assert-MockCalled -CommandName Invoke-WebRequest -Exactly -Times 0
            Assert-MockCalled -CommandName New-ExceptionDetail -Exactly -Times 0
        }

        It "should validate key missing and throw" {

            {Remove-A0User -baseURL $formedURL -email} | Should Throw

            Assert-MockCalled -CommandName Invoke-WebRequest -Exactly -Times 0
            Assert-MockCalled -CommandName New-ExceptionDetail -Exactly -Times 0
        }


    }

    Context "Call Auth0" {

        It "should Invoke-WebRequest and return response" {

            Get-A0UserByEmail -baseURL $formedURL -email $testEmail | Should not be $null

            Assert-VerifiableMocks
        }

    }

    Context "Call Auth0 and fail" {

        Mock -CommandName Invoke-WebRequest -Verifiable -MockWith {
        
            Throw
        }

        It "should throw exception" {

            {Get-A0UserByEmail -baseURL $formedURL -email $testEmail} | Should Throw

        }

        Assert-VerifiableMocks
        Assert-MockCalled -CommandName New-ExceptionDetail -Exactly -Times 1


    }
}
