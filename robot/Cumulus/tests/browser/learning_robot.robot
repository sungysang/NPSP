*** Settings ***

Resource        robot/Cumulus/resources/NPSP.robot
Library         cumulusci.robotframework.PageObjects
...             robot/Cumulus/resources/GAUPageObject.py
...             robot/Cumulus/resources/OpportunityPageObject.py
Suite Setup     Run Keywords
...             Setup Test Data
...             Open Test Browser
Suite Teardown  Delete Records and Close Browser


*** Keywords ***
Setup Test Data
        &{campaign}=                      API Create Campaign  
        &{data}=                          setupdata                                     contact          ${contact1_fields}          
        Set suite Variable                &{campaign}
        Set suite Variable                &{data}


*** Variables ***    
&{contact1_fields}       Email=test@example.com
${amount}                100
${stage_name}            Closed Won


*** Test Cases ***
Assign GAU to Campaign and Verify Allocation on Opportunity
        Go To Page                           Listing
        ...                                  General_Accounting_Unit__c 
        ${gau1_name}=                        Generate Random String
        Click Object Button                  New
        Populate Modal Form
        ...                                  General Accounting Unit Name=${gau1_name}
        Click Modal Button                   Save
        Wait Until Modal Is Closed
        ${gau_header}=                       Get Main Header
        ${gau1}=                             Save Current Record Id For Deletion      General_Accounting_Unit__c
        Select Tab                           Related
        Click Object Button                  New
        Populate Modal Form                  Percent=100
        ...                                  Campaign=&{campaign}[Name]
        Click Modal Button                   Save
        Go To Page                           Listing
        ...                                  Opportunity
        ${opportunity_name}=                 Generate Random String
        Click Object Button                  New
        Select Record Type                   Donation
        Populate Modal Form
        ...                                  Opportunity Name=${opportunity_name}
        ...                                  Account Name=${data}[contact][LastName] Household
        ...                                  Amount=${amount}
        ...                                  Primary Campaign Source=${campaign}[Name]
        Select Value From Dropdown           Stage      ${stage_name}
        Open Date Picker                     Close Date
        Pick Date                            Today
        Click Modal Button                   Save 
        Select Tab                           Related    
        Validate Related Record Count        GAU Allocations         1                                