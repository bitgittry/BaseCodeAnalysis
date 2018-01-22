DROP procedure IF EXISTS `GameUpdateTableSizes`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `GameUpdateTableSizes`()
BEGIN

	insert into gaming_table_sizes 
		SELECT 
		DATE(NOW()) 'date',
		Table_name as 'table_name',
		round(table_rows/1000,3) 'rows_kb',
		round(data_length/(1024*1024),3) 'data_mb',
		round(index_length/(1024*1024),3) 'index_mb',
		round(index_length/(1024*1024),3) 'free_mb',
		round((data_length+index_length)/(1024*1024),3) 'total_size_mb'
		FROM information_schema.TABLES where table_schema = database()
		ORDER BY Table_name;

END$$

DELIMITER ;