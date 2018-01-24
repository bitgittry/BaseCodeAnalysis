DROP procedure IF EXISTS `QueryDatesGenerate`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `QueryDatesGenerate`(deletePrevious TINYINT(1), dateFromContinueFromLast TINYINT(1), queryDateIntervalType VARCHAR(10), startDate DATETIME, endDate DATETIME, OUT statusCode INT)
root:BEGIN
  
  -- Change MICROSECOND to SECOND for WEEK
  
  
  DECLARE queryDateIntervalTypeID, lastQueryDateIntervalID BIGINT DEFAULT -1;
  DECLARE intVal INT DEFAULT 0;
  DECLARE unitVal VARCHAR(10);
  DECLARE allowGenerateUnits TINYINT(1) DEFAULT 0;
  DECLARE dateDisplay VARCHAR(80);
  
  DECLARE countPrevious INT DEFAULT 0;
  
  DECLARE thisDate DATETIME;
  DECLARE nextDate DATETIME;
  DECLARE nextDateSubMicroTemp, weekYearNextTemp, lastDateTo DATETIME;
  DECLARE occurenceNum INT DEFAULT 0; 
  
  SET weekYearNextTemp = NULL;
  SET statusCode=10;
  
  
  
  SELECT query_date_interval_type_id, unit_val, int_val, allow_generate_units  
  INTO queryDateIntervalTypeID, unitVal, intVal, allowGenerateUnits 
  FROM gaming_query_date_interval_types 
  WHERE name=queryDateIntervalType;
 
  
  IF (queryDateIntervalTypeID=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  IF (allowGenerateUnits=0) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
   
  
  IF (deletePrevious=1) THEN 
    DELETE FROM gaming_query_date_intervals 
    WHERE query_date_interval_type_id=queryDateIntervalTypeID;
    
    
    SELECT COUNT(query_date_interval_id) INTO countPrevious   
    FROM gaming_query_date_intervals 
    WHERE query_date_interval_type_id=queryDateIntervalTypeID;
    
    IF (countPrevious<>0) THEN
      SET statusCode=3;
      LEAVE root;
    END IF;
  END IF;
  
  IF (dateFromContinueFromLast) THEN
    
    SELECT query_date_interval_id, date_interval_num, date_to INTO lastQueryDateIntervalID, occurenceNum, lastDateTo
    FROM gaming_query_date_intervals 
    WHERE query_date_interval_type_id=queryDateIntervalTypeID
    ORDER BY date_interval_num DESC
    LIMIT 1;
  
    IF (lastQueryDateIntervalID=-1) THEN
      SET statusCode=4;
      LEAVE root;
    END IF;
  
    SET startDate=DATE_ADD(lastDateTo, INTERVAL 1 SECOND);
  END IF;
  
  
  SET thisDate = DATE(startdate);
  SET endDate = endDate; 
  
  
  
  REPEAT
    SET occurenceNum = occurenceNum + 1;
    SET dateDisplay = '-';
    
      CASE unitVal
          WHEN 'MICROSECOND' THEN 
            BEGIN
              SET nextDate = DATE_ADD(thisDate, INTERVAL intVal MICROSECOND);
            END;
          WHEN 'SECOND'      THEN 
            BEGIN
              SET nextDate = DATE_ADD(thisDate, INTERVAL intVal SECOND);
            END;
          WHEN 'MINUTE'      THEN 
            BEGIN
              SET nextDate = DATE_ADD(thisDate, INTERVAL intVal MINUTE);
            END;
          WHEN 'HOUR'        THEN 
            BEGIN
              SET nextDate = DATE_ADD(thisDate, INTERVAL intVal HOUR);
              SET dateDisplay = DATE_FORMAT(thisDate, '%Y-%m-%d %H:00');
            END;
          WHEN 'DAY'         THEN 
            BEGIN 
              SET nextDate = DATE_ADD(thisDate, INTERVAL intVal DAY);
              SET dateDisplay = DATE_FORMAT(thisDate, '%Y-%m-%d');
            END;
          WHEN 'WEEK'        THEN 
            BEGIN
              IF weekYearNextTemp IS NOT NULL THEN
                SET nextDate = weekYearNextTemp;
              ELSE
                SET nextDate = DATE_ADD(thisDate, INTERVAL intVal WEEK);
              END IF;
              SET nextDateSubMicroTemp = DATE_ADD(nextDate, INTERVAL -1 SECOND);
              
              SET weekYearNextTemp = NULL;
              IF (YEAR(thisDate)<>YEAR(nextDateSubMicroTemp)) THEN 
                SET weekYearNextTemp = nextDate;
                SET nextDate = DATE_FORMAT(nextDate,'%Y-01-01 00:00:00');
                SET nextDateSubMicroTemp = DATE_ADD(nextDate, INTERVAL -1 SECOND);
              END IF;
              SET dateDisplay = CONCAT(DATE_FORMAT(thisDate, '%Y - W%u (%m-%d .. '),DATE_FORMAT(nextDateSubMicroTemp,'%m-%d'),')');
            END;
          WHEN 'MONTH'       THEN 
            BEGIN 
              SET nextDate = DATE_ADD(thisDate, INTERVAL intVal MONTH);
              SET dateDisplay = DATE_FORMAT(thisDate, '%Y - %m');
            END;
          WHEN 'QUARTER'     THEN 
            BEGIN 
              SET nextDate = DATE_ADD(thisDate, INTERVAL intVal QUARTER);
              SET dateDisplay = CONCAT(YEAR(thisDate),' - Q',QUARTER(thisDate));
            END;
          WHEN 'YEAR'        THEN 
            BEGIN 
              SET nextDate = DATE_ADD(thisDate, INTERVAL intVal YEAR);
              SET dateDisplay = DATE_FORMAT(thisDate, '%Y');
            END;
        END CASE;
    
	INSERT INTO gaming_query_date_intervals (query_date_interval_type_id, date_from, date_to, date_interval_num, date_display) 
    SELECT queryDateIntervalTypeID, thisDate, DATE_ADD(nextDate, INTERVAL -1 SECOND), occurenceNum, dateDisplay;
    
    SET thisDate = nextDate;
  UNTIL thisDate >= enddate
  END REPEAT;
  SET statusCode=0;
END root$$

DELIMITER ;

