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
        &{campaign}=                         API Create Campaign  
        &{data}=                             setupdata                                     contact          ${contact1_fields}   
        ${ns}=                               Get Npsp Namespace Prefix
        Set suite Variable                   &{campaign}
        Set suite Variable                   &{data}
        Set suite Variable                   ${ns}

Create GAU      
        ${name}=                             Generate Random String
        Go To Page                           Listing
        ...                                  General_Accounting_Unit__c
        Click Object Button                  New
        Populate Modal Form 
        ...                                  General Accounting Unit Name=${name}
        Click Modal Button                   Save
        Wait Until Modal Is Closed
        ${gau_id}=                           Save Current Record Id For Deletion                General_Accounting_Unit__c
        [return]                             ${gau_id}

Create Opportunity With Campaign
        [Arguments]     ${account_name}         ${campaign_name}
        Go To Page                           Listing
        ...                                  Opportunity
        ${opportunity_name}=                 Generate Random String
        Click Object Button                  New
        Select Record Type                   Donation
        Populate Modal Form
        ...                                  Opportunity Name=${opportunity_name}
        ...                                  Account Name=${account_name}
        ...                                  Amount=${amount}
        ...                                  Primary Campaign Source=${campaign_name}
        Select Value From Dropdown           Stage      ${stage_name}
        Open Date Picker                     Close Date
        Pick Date                            Today
        Click Modal Button                   Save 
        Wait Until Modal Is Closed
        ${opp_id}=                           Save Current Record Id For Deletion                Opportunity
        [return]                             ${opp_id}

API Create Campaign GAU Allocation
        [Arguments]     ${gau_id}       ${campaign_id}          &{fields}
        ${ns}=                               Get Npsp Namespace Prefix
        ${all_id}=                           Salesforce Insert                   
        ...                                  ${ns}Allocation__c
        ...                                  ${ns}General_Accounting_Unit__c=${gau_id}
        ...                                  ${ns}Campaign__c=${campaign_id}
        ...                                  &{fields}
        &{gau_alloc}=                        Salesforce Get  ${ns}Allocation__c  ${all_id}
        [return]                             &{gau_alloc} 

Browser Create Campaign GAU Allocation
        [Arguments]     ${campaign_name}
        Select Tab                           Related
        Click Object Button                  New
        Populate Modal Form                  Percent=100
        ...                                  Campaign=${campaign_name}
        Click Modal Button                   Save

Verify GAU Allocation is Automatically Created
        Select Tab                           Related    
        Validate Related Record Count        GAU Allocations         1        


*** Variables ***    
&{contact1_fields}       Email=test@example.com
${amount}                100
${stage_name}            Closed Won


*** Test Cases ***
Assign GAU to Campaign and Verify Allocation on Opportunity
        ${gau_id}=                           Create GAU                          
        API Create Campaign GAU Allocation   ${gau_id}
        ...                                  &{campaign}[Id]
        ...                                  ${ns}Percent__c=100.0 
        Create Opportunity With Campaign     ${data}[contact][LastName] Household  
        ...                                  ${campaign}[Name]
        Verify GAU Allocation is Automatically Created                              