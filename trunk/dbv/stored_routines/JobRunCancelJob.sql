DROP procedure IF EXISTS `JobRunCancelJob`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `JobRunCancelJob`(jobID BIGINT)
BEGIN
  -- removed query on job_runs

  UPDATE gaming_jobs
  JOIN gaming_job_execution_statuses AS current_job_status ON current_job_status.name='Processing' AND gaming_jobs.job_execution_status_id=current_job_status.job_execution_status_id
  JOIN gaming_job_execution_statuses AS new_job_status ON new_job_status.name='NonProcessing' 
  SET gaming_jobs.job_execution_status_id=new_job_status.job_execution_status_id
  WHERE (jobID=0 OR gaming_jobs.job_id=jobID);
  
END$$

DELIMITER ;

