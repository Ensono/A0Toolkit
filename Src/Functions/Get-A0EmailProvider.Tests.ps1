$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut"


# // START test setup //

$malformedURL = "http:/url.com"
$formedURL = "http://url.com"

$testExceptionMessage = "test exception"

. "$here\Private\New-ExceptionDetail.ps1"

# // END test setup //



Describe "Get-A0EmailProvider" {

    Mock -CommandName Invoke-WebRequest -Verifiable -MockWith {@{}}

    Mock -CommandName New-ExceptionDetail
    
    Context "Parameter validation fails" {        

        It "should validate malformed URL and throw" {

            {Get-A0EmailProvider -baseURL $malformedURL } | Should Throw

            Assert-MockCalled -CommandName Invoke-WebRequest -Exactly -Times 0
            Assert-MockCalled -CommandName New-ExceptionDetail -Exactly -Times 0
        }


    }

    Context "Call Auth0" {

        It "should Invoke-WebRequest and return response" {

            Get-A0EmailProvider -baseURL $formedURL | Should not be $null

            Assert-VerifiableMocks
        }

    }

    Context "Call Auth0 and fail with 404" {

        Mock -CommandName Invoke-WebRequest -Verifiable -MockWith {
        
            Throw (@{'statusCode' = 404} | ConvertTo-Json)
        }

        It "should not throw an exception and return" {

            Get-A0EmailProvider -baseURL $formedURL | Should be $null

        }

        Assert-VerifiableMocks
        Assert-MockCalled -CommandName New-ExceptionDetail -Exactly -Times 0


    }

    Context "Call Auth0 and fail" {

        Mock -CommandName Invoke-WebRequest -Verifiable -MockWith {
        
            Throw (@{'statusCode' = 500} | ConvertTo-Json)
        }

        It "should throw exception" {

            {Get-A0EmailProvider -baseURL $formedURL} | Should Throw

        }

        Assert-VerifiableMocks
        Assert-MockCalled -CommandName New-ExceptionDetail -Exactly -Times 1


    }
}
