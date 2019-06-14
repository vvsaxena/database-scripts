DROP PROCEDURE IF EXISTS drop_old_partitions;

DELIMITER $$
CREATE PROCEDURE drop_old_partitions(p_schema varchar(100),p_table varchar(100),p_min_to_keep int,p_to_purge int, p_seconds_to_sleep int)
   LANGUAGE SQL
   NOT DETERMINISTIC
   SQL SECURITY INVOKER
BEGIN
        declare partname char(20);

        SET @maxNumber = p_to_purge;
        SET @pschema = p_schema;
        SET @ptable= p_table;
        SET @pmin= p_min_to_keep;
        SET @CNT=1;

        select count(*) from information_schema.partitions WHERE table_schema=@pschema AND table_name=@ptable into @total_partitions;

        IF @total_partitions > @pmin THEN

                -- Start the loop until max number of partitions dropped
                myloop: while @CNT <= @maxNumber do


                                -- Get the oldest partition name
                                select PARTITION_NAME  FROM information_schema.partitions WHERE table_schema=@pschema AND table_name=@ptable ORDER BY partition_description limit 1 into partname;
                                SET @partition = partname;

                                SET @q = 'SELECT CONCAT('' DROPPING PARTITION   '', @partition)';
                                PREPARE st FROM @q;
                                EXECUTE st;
                                DEALLOCATE PREPARE st;

                                SET @q = 'SELECT CONCAT(''ALTER TABLE '', @pschema,''.'',@ptable, '' DROP PARTITION '', @partition) INTO @query';
                                PREPARE st FROM @q;
                                EXECUTE st;
                                DEALLOCATE PREPARE st;

                                -- And then we prepare and execute the ALTER TABLE query.
                                PREPARE st FROM @query;
                                EXECUTE st;
                                DEALLOCATE PREPARE st;

                                -- Increment the counter for next oldest partition
                                set @CNT = @CNT + 1;

                                -- Sleep for interval given in between the process

                                SELECT CONCAT('Sleeping for ', p_seconds_to_sleep, ' seconds');
                                SELECT SLEEP(p_seconds_to_sleep);

                        select count(*) from information_schema.partitions WHERE table_schema=@pschema AND table_name=@ptable into @local_totalpart;

                        select @local_totalpart, @total_partitions;

                        IF @local_totalpart <= @pmin THEN
                                SET @q = 'SELECT CONCAT('' TOTAL AVAILABLE PARTITIONS ARE NOT GREATER THEN   '', @pmin, '' SO NOT DROPPING ANY MORE PARTITIONS'')';
                                PREPARE st FROM @q;
                                EXECUTE st;
                                DEALLOCATE PREPARE st;
                                LEAVE myloop;
                        END IF;

                END WHILE myloop;

        ELSE

                SET @q = 'SELECT CONCAT('' TOTAL AVAILABLE PARTITIONS ARE NOT GREATER THEN   '', @pmin, '' SO NOT DROPPING ANY PARTITIONS'')';
                PREPARE st FROM @q;
                EXECUTE st;
                DEALLOCATE PREPARE st;

        END IF;
END$$
DELIMITER ;
