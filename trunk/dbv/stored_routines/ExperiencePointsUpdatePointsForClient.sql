DROP procedure IF EXISTS `ExperiencePointsUpdatePointsForClient`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `ExperiencePointsUpdatePointsForClient`(clientID BIGINT, experiencePointsAmount INT, licenseTypeID INT, varReason TEXT, userID BIGINT, OUT statusCode INT)
root:BEGIN

  DECLARE licenseType INT DEFAULT 0;
  DECLARE totalExperiencePoints INT DEFAULT 0;
  DECLARE ClientIDTemp BIGINT DEFAULT 0;
  SET statusCode=0;
  
  SELECT license_type_id INTO licenseType FROM gaming_license_type WHERE license_type_id=licenseTypeID;
  
  IF licenseType=0 THEN 
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  SELECT client_id INTO ClientIDTemp FROM gaming_clients WHERE client_id=clientID;
  IF ClientIDTemp=0 THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
      
  INSERT INTO gaming_clients_experience_points (client_id,license_type_id,amount_total) VALUES
  (clientID,licenseTypeID,experiencePointsAmount)
  ON DUPLICATE KEY UPDATE amount_total= amount_total+experiencePointsAmount;
   
  INSERT INTO gaming_clients_experience_points_transactions (client_id,time_stamp,amount_given,amount_total,license_type_id)
  SELECT clientID,NOW(),experiencePointsAmount,amount_total,licenseType
  FROM gaming_clients_experience_points WHERE client_id=clientID AND license_type_id=licenseType;

  INSERT INTO gaming_event_rows (event_table_id, elem_id) 
  SELECT gaming_event_tables.event_table_id,LAST_INSERT_ID()
  FROM gaming_event_tables 
  WHERE gaming_event_tables.table_name='gaming_clients_experience_points_transactions'; 
   
END$$

DELIMITER ;

