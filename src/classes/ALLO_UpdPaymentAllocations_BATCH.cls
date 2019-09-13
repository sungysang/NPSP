/*
    Copyright (c) 2019, Salesforce.org
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Salesforce.org nor the names of
      its contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
    COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.
*/
/**
* @author Salesforce.org
* @date 2019
* @group Allocations
* @group-content ../../ApexDocContent/Allocations.htm
* @description Batch Job to update/recalculate Payment Allocations (Main Batch, Driven by Opportunity Object)
*/
public class ALLO_UpdPaymentAllocations_BATCH extends UTIL_AbstractCommon_BATCH {

    public class AlloPaymentAllocationBatchException extends Exception { }

    public static final String PROCESS_NAME = 'Payment Allocations Batch';

    private static Allocations_Settings__c allocationsSettings = UTIL_CustomSettingsFacade.getAllocationsSettings();

    private DateTime jobStart;
    private DateTime boundary;
    private Integer recCnt;
    private Integer reviewCnt;
    private Boolean paymentAllocConfigurationValid;

   /**
     * Constructor (takes no arguments)
     */
     public ALLO_UpdPaymentAllocations_BATCH() {
        super();
        initialize();
    }

    /**
     * Constructor (takes batchSize as parameters)
     * @param  batchSize Controls the number of records that can be processed in a batch
     */
    public ALLO_UpdPaymentAllocations_BATCH(Integer batchSize) {
        super(batchSize);
        initialize();
    }

    /**
     * Constructor (takes batchSize, additionalWhere as parameters)
     * @param  batchSize Controls the number of records that can be processed in a batch
     * @param  additionalWhereClause Any additional whereclause fragment to add to the batch job
     */
    public ALLO_UpdPaymentAllocations_BATCH(Integer batchSize, String additionalWhereClause) {
        super(batchSize, additionalWhereClause);
        initialize();
    }

    /**
     * @description Sets up various tracking/usage variables, and looks up the current boundary timestamp (or defaults it if not already present)
     */
    private void initialize() {
        this.recCnt = 0;
        this.reviewCnt = 0;
        this.boundary = (allocationsSettings != null && allocationsSettings.LastJobStartTimePaymentAllocations__c != null) ?
                        allocationsSettings.LastJobStartTimePaymentAllocations__c : System.now().addYears(-1);

    }

    /**
     * @description Called on Batches start.  Used to capture the jobStart timestamp, and to validate the Payment Allocations configuration
     * @param bc BatchableContext provided by Salesforce
     * @param firstChunk Boolean indicating this is the first execution of the start method.
     */
    public override void onStart(Database.BatchableContext bc, Boolean firstChunk) {
        if (this.jobStart == null) {
            this.jobStart = System.now();
        }
        this.paymentAllocConfigurationValid = validatePaymentAllocationsConfiguration(PROCESS_NAME);
    }

    /**
     * @description Validates that Payment Allocations are configured correctly.  Returns false if not correct.  Also logs an error.
     * Returns true, if there are no Payment Allocation configuration Issues
     * @param processName Name of Process Configuration Errors should be associated with
     * @returns Boolean true if Payment Allocations Config is valid, and false otherwise
     */
    public static Boolean validatePaymentAllocationsConfiguration(String processName) {
        List<String> paCfgProblems = ALLO_AllocationsUtil.validatePaymentAllocationsConfiguration();
        if (paCfgProblems.size() > 0) {
            String errorMsg = System.Label.alloPaymentAllocationBatchConfigError + '\r\n' + String.join(paCfgProblems, '\r\n');
            AlloPaymentAllocationBatchException apabe = new AlloPaymentAllocationBatchException(errorMsg);

            ERR_Handler.processError(apabe, processName);
        }
        // Valid if no messages added
        return (paCfgProblems.size() == 0);
    }

    /**
     * @description Invoked here per batch
     * @param bc BatchableContext
     * @param records The list of records returned for this batch, filtered for any additionalWhere clause added, and including the fields/subqueries configured for this batch
     */
    public override void doExecute(Database.BatchableContext bc, List<SObject>records ) {

        Set<Id> oppIds = addIdsForRecords(new Set<Id>(), records);

        // We want to disable Allocation Triggers, do not have a RecordErrors Map to pass in, and want to commit and clear any errors (Calls this to do actual processing)
        processRecords(PROCESS_NAME, oppIds, null, this.boundary, true, true);
    }

    /**
     * @description Actual processing occurs in this method
     * @param String processName Name of Process Error Records should be associated with
     * @param Set<Id> oppIds Set of Opportunity Ids to review and process
     * @param ERR_RecordError recErrs Instance of the ERR_RecordError class.  If populated, will use this.  If not, it will initialize and retrieve records
     *        for this batch
     * @param Datetime boundary Used to find records modified since last execution
     * @param Boolean disableAllocationTriggers Indicates whether or not the ALLO_Allocation_TDTM and ALLO_PaymentSync_TDTM triggers should be allowed to run
     * @param Boolean commitAndClearRecordErrors Should we commit and clear record errors here, or delegate it to the caller.
     */
    public static Set<Id> processRecords(String processName, Set<Id> oppIds, ERR_RecordError recErrs, Datetime boundary, Boolean disableAllocationTriggers, Boolean commitAndClearRecordErrors) {

        ALLO_AllocationsUtil.RecordsForReview recs = ALLO_AllocationsUtil.determineRecordsRequiringReview(PROCESS_NAME, oppIds, boundary, recErrs);

        if (disableAllocationTriggers) {
            // Disable Allocation Triggers prior to making any DML Updates
            ALLO_AllocationsUtil.disableAllocationTriggers();
        }

        // Will track exclusions across processes
        ALLO_AllocationsUtil.RecordExclusions recExcl = new ALLO_AllocationsUtil.RecordExclusions();

        // Process Opportunity Allocations
        ALLO_AllocationsUtil.AllocationResults allocResults = ALLO_AllocationsUtil.processOpportunityAllocations(recs.oppsById, recs.oppsAllocations, recs.campaignAllocations, recs.recurringDonationAllocations, recExcl);

        // Process Opportunity Allocation Results
        ALLO_AllocationsUtil.processAllocationResults(ALLO_AllocationsUtil.PROCESS_DEF.OPP_ALLOC_UPD, allocResults, recs, recExcl);

        // Process Payment Allocations
        allocResults = ALLO_AllocationsUtil.processPaymentAllocations(recs.oppsById, recs.oppsAllocations, recs.paymentAllocations, recExcl);

        // Process Payment Allocations Results
        ALLO_AllocationsUtil.processAllocationResults(ALLO_AllocationsUtil.PROCESS_DEF.PMT_ALLOC, allocResults, recs, recExcl);

        // Determine successfully processed errors
        Set<Id> successfullyProcessed = ALLO_AllocationsUtil.determineSucessfullyProcessedRecords(oppIds, recExcl);

        if (commitAndClearRecordErrors) {
            // Clear Retry Pending and add Retry Successful for Records that were successful that have existing errors flagged for Retry
            recs.recErrs.clearErrors(successfullyProcessed, Label.errErrorRecordRetrySuccessful);
            // Commit all pending errors
            recs.recErrs.processErrors();
        }

        if (disableAllocationTriggers) {
            // Enable Allocation Triggers after all updates are complete
            ALLO_AllocationsUtil.enableAllocationTriggers();
        }

        return successfullyProcessed;

    }



    /**
     * @description Takes a set of Ids, and adds additional record Ids to it from the list of records
     * @param Set<Id> ids The set of Ids to add to
     * @param List<SObject> records The records to be added to the Set of Ids
     * @return Set<Id> the updated Set of Ids
     */
    private Set<Id> addIdsForRecords(Set<Id> ids, List<SObject> records) {

        for (SObject rec : records) {
            ids.add(rec.Id);
        }
        return ids;
    }

    /**
     * @description In this case, the main driver will be the Opportunity
     * @return Opportunity's SObjectType
     */
    public override SObjectType getSObjectType() {
        return Opportunity.getSObjectType();
    }

    /**
     * @description If Payment Allocations Configuration is Invalid, it will short circuit the batch so it does not process any records
     * @return String Where clause
     */
    public override String getWhereClause() {

        return (!this.paymentAllocConfigurationValid) ? 'Name=\'\'' : '';
    }

    /**
     * @description Records the most recent time this job started.  Executes the Error Phase.  These only occur in the final iteration of the Batch
     * @param bc BatchableContext
     * @param isComplete boolean value that indicates whether or not this is the final invocation, or will be executing against additional chunks
     */
    public override void doFinish(Database.BatchableContext bc , Boolean isComplete) {
        // Only update the LastJobStartTime for this Batch, and execute the Error Batch if the Payment Allocations Configuration is valid and this Batch if fully complete (has completed all chunks, if LDVMode or has finished processing if non LDV Mode)
        if (isComplete && this.paymentAllocConfigurationValid) {
            allocationsSettings.LastJobStartTimePaymentAllocations__c = this.jobStart;
            upsert allocationsSettings;

            // Execute Error Batch Phase
            ALLO_UpdPaymentAllocations_ERR_BATCH alloErrBatch = new ALLO_UpdPaymentAllocations_ERR_BATCH(getBatchSize(), this.jobStart);
            Database.executeBatch(alloErrBatch, this.getBatchSize());
        }
    }

}