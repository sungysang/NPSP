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
* @group Batch Job
* @description Batch job service
*/
public with sharing class UTIL_BatchJobService {
    public class BatchException extends Exception {}

    @TestVisible
    private static final String BATCH_JOB_REQUIRED = 'Batch job is required';

    private static final String JOB_TYPE_BATCH = 'BatchApex';

    public enum ApexJobStatus { 
        HOLDING, QUEUED, PREPARING, PROCESSING, COMPLETED, FAILED, ABORTED 
    }

    public static final Set<String> IN_PROGRESS_STATUSES = new Set<String>{
        ApexJobStatus.HOLDING.name(),
        ApexJobStatus.QUEUED.name(),
        ApexJobStatus.PREPARING.name(),
        ApexJobStatus.PROCESSING.name()
    };

    /***
    * @description Determines if the batch job is in progress
    * @param batchId Batch Id
    * @return Boolean
    */
    public Boolean isInProgress(Id batchId) {
        if (batchId == null) {
            return false;
        }

        return (Database.countQuery('SELECT Count() FROM AsyncApexJob WHERE Id = :batchId AND Status IN :IN_PROGRESS_STATUSES') > 0);
    }

    /***
    * @description Loads the latest batch job for the specified batch class name
    * @param className Batch class name
    * @return BatchJob
    */
    public BatchJob getBatchJob(String className) {
        String namespacePrefix = UTIL_Namespace.getNamespace();

        List<AsyncApexJob> apexJobs = [
            SELECT
                Status, ExtendedStatus, NumberOfErrors,
                TotalJobItems, JobItemsProcessed,
                CreatedDate, CompletedDate
            FROM AsyncApexJob
            WHERE JobType = :JOB_TYPE_BATCH
                AND ApexClass.Name = :className
                AND ApexClass.NamespacePrefix = :namespacePrefix
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        return apexJobs.isEmpty() ? null : new BatchJob(apexJobs[0]);
    }


    /***
    * @description Batch job descriptor
    */
    public class BatchJob {

        public Id batchId;
        public String status;
        public String extendedStatus;
        public Integer jobItemsProcessed;
        public Integer totalJobItems;
        public Integer numberOfErrors;

        @TestVisible 
        private DateTime createdDate;
        public DateTime completedDate;

        public String timeElapsed;
        public Long percentComplete = 0;
        public Boolean isInProgress = false;

        /***
        * @description Constructor
        * @param job AsyncApexJob record
        */
        public BatchJob(AsyncApexJob job) {
            if (job == null) {
                throw new BatchException(BATCH_JOB_REQUIRED);
            }

            batchId = job.Id;
            status = job.Status;
            extendedStatus = job.ExtendedStatus;
            jobItemsProcessed = job.JobItemsProcessed;
            totalJobItems = job.TotalJobItems;
            numberOfErrors = job.NumberOfErrors;

            createdDate = job.CreatedDate;
            completedDate = job.CompletedDate;

            timeElapsed = calcTimeElapsed(createdDate, completedDate);
            percentComplete = calcPercentComplete(jobItemsProcessed, totalJobItems, status);
            isInProgress = isInProgress(status);
        }

        /***
        * @description Calculates time elapsed since the batch job has started. 
        * 
        * @param startDate Batch Start Date
        * @param endDate When completed, the endDate is completion date; 
        * otherwise, the endDate is the current datetime.
        * @return String Time elapsed
        */
        @TestVisible
        private String calcTimeElapsed(DateTime startDate, DateTime endDate) {
            endDate = endDate == null ? Datetime.now() : endDate;

            Long milliseconds = endDate.getTime() - startDate.getTime();
            Long days = milliseconds / 1000 /60 /60 /24;

            DateTime diffDate = DateTime.newInstance(milliseconds);

            return (days > 0 ? String.valueOf(days) + ' ' + System.Label.BatchProgressTimeElapsedDays + ' ' : '') +
                String.format(
                    '{0}:{1}:{2}', 
                    new String[] { formatTime(diffDate.hourGmt()), formatTime(diffDate.minuteGmt()), formatTime(diffDate.secondGmt()) }
                );
        }

        /***
        * @description Formats hours, minutes and seconds of the time
        * @param value Time
        * @return String Formatted time
        */
        private String formatTime(Long value) {
            return String.valueOf(value).leftPad(2, '0').right(2);
        }

        /***
        * @description Calculates the percentage of the batch job completion
        * @param jobItemsProcessed Processed batch iterations
        * @param totalJobItems Total batch iterations
        * @param status Batch job status
        * @return Long Percentage completed
        */
        @TestVisible
        private Long calcPercentComplete(Integer jobItemsProcessed, Integer totalJobItems, String status) {
            final Integer defaultPercentComplete = 5;

            Long percentComplete = defaultPercentComplete;

            if (ApexJobStatus.COMPLETED.name() == status) {
                percentComplete = 100;

            } else if (ApexJobStatus.QUEUED.name() == status || ApexJobStatus.HOLDING.name() == status) {
                percentComplete = defaultPercentComplete;

            } else if (ApexJobStatus.PREPARING.name() == status) {
                percentComplete = 10;

            } else if (ApexJobStatus.FAILED.name() == status) {
                percentComplete = 0;

            } else if (0 == totalJobItems) {
                percentComplete = defaultPercentComplete;

            } else {
                percentComplete = Math.max(
                    Math.roundToLong(100 * jobItemsProcessed / totalJobItems), 
                    defaultPercentComplete
                );
            }

            return percentComplete;
        }

        /***
        * @description Determines if the batch job is in progress
        * @param status Batch job status
        * @return Boolean
        */
        @TestVisible
        private Boolean isInProgress(String status) {
            return IN_PROGRESS_STATUSES.contains(status.toUpperCase());
        }

    }

}