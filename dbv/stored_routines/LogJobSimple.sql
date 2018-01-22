DROP procedure IF EXISTS `LogJobSimple`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LogJobSimple`(jobRunID BIGINT, jobName VARCHAR(50), message TEXT)
root: BEGIN

  DECLARE v_jobRunID BIGINT;
  DECLARE v_jobName VARCHAR(50);
  
  SELECT job_run_id INTO v_jobRunID FROM gaming_job_runs WHERE job_run_id = jobRunID;
  SET v_jobName = ifnull(jobName, '');
  
  IF (v_jobRunID is null or 0 = length(v_jobName)) THEN
    LEAVE root;
  END IF;
    
  INSERT INTO gaming_log_simples (`operation_name`, `inputs`, `exception_message`, `date_added`)
    VALUES (jobName, CONCAT('[{"jobRunID":', jobRunID,'}]'), message, CURRENT_TIMESTAMP);

END root$$

DELIMITER ;
