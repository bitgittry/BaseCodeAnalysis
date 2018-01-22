DROP procedure IF EXISTS `JobRunOnStart`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `JobRunOnStart`(jobID BIGINT, runNowOverride TINYINT(1), OUT statusCode INT)
root: BEGIN
  -- Fixed deadlock issue because was locking also on job status   

  DECLARE jobIDCheck, jobRunID, jobExecutionStatusID BIGINT DEFAULT -1;
  DECLARE jobExecutionStatus VARCHAR(80);
  
  SELECT gaming_jobs.job_id, gaming_jobs.job_execution_status_id INTO jobIDCheck, jobExecutionStatusID
  FROM gaming_jobs
  WHERE gaming_jobs.job_id=jobID AND gaming_jobs.is_enabled=1 AND gaming_jobs.is_suspended=0;
  
  IF (jobIDCheck=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  SELECT current_job_status.name INTO jobExecutionStatus
  FROM gaming_job_execution_statuses AS current_job_status
  WHERE current_job_status.job_execution_status_id = jobExecutionStatusID;
  
  IF (jobExecutionStatus!='NonProcessing') THEN
    CALL JobRunCancelJob(jobID);
  END IF;
  
  SET jobIDCheck=-1;
  
  SELECT gaming_jobs.job_id INTO jobIDCheck
  FROM gaming_jobs
  WHERE gaming_jobs.job_id=jobID AND
   (is_recurring=0 OR (runNowOverride=1 OR NOW() BETWEEN recurring_date_from and recurring_date_to)) AND 
   (recurring_num_times IS NULL OR num_times_executed<recurring_num_times) AND 
   (is_recurring=1 OR num_times_executed=0) AND 
   (next_run_date IS NOT NULL AND (runNowOverride=1 OR NOW()>=DATE_SUB(next_run_date, INTERVAL 10 MINUTE))) 
  FOR UPDATE;
  
  IF (jobIDCheck=-1) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  UPDATE gaming_jobs
  JOIN gaming_job_execution_statuses AS job_new_status ON job_new_status.name='Processing'
  SET gaming_jobs.job_execution_status_id=job_new_status.job_execution_status_id
  WHERE gaming_jobs.job_id=jobID;
  
  INSERT INTO gaming_job_runs (job_id, job_execution_status_id, query_date_interval_id, start_date, session_id)
  SELECT gaming_jobs.job_id, gaming_job_execution_statuses.job_execution_status_id, gaming_jobs.current_query_date_interval_id, NOW(), 0
  FROM gaming_jobs
  JOIN gaming_job_execution_statuses ON gaming_jobs.job_id=jobID AND gaming_job_execution_statuses.name='Processing';
  
  SET jobRunID=LAST_INSERT_ID();
  
  IF (jobRunID=-1) THEN
    SET statusCode=3;
    LEAVE root;
  END IF;
  
  SELECT job_run_id, job_id, gaming_job_execution_statuses.name AS job_execution_status, query_date_interval_id, start_date, end_date, message
  FROM gaming_job_runs 
  JOIN gaming_job_execution_statuses ON gaming_job_runs.job_execution_status_id=gaming_job_execution_statuses.job_execution_status_id
  WHERE gaming_job_runs.job_run_id=jobRunID;
  
  SET statusCode=0;
END root$$

DELIMITER ;

