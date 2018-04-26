#!/bin/bash
# line:           V1.0
# mail:           gczheng@139.com
# data:           2018-04-25
# script_name:    bak_mysql_all.sh
# database_host:  192.168.49.246
# crontab:        30 0 * * *  /bin/sh  /scripts/bak_mysql.sh full >/dev/null 2>&1
# crontab:        30 0 * * *  /bin/sh  /scripts/bak_mysql.sh incr >/dev/null 2>&1
#=======================================================================
#设置环境变量
#=======================================================================
source /etc/profile
#=======================================================================
#设置时间
#=======================================================================

DATE=`date +%Y%m%d`
DATE2=`date "+%Y%m%d%H%M%S"`
#=======================================================================
#设置帐号和密码
#=======================================================================
MY_USER="gcdb"
MY_PASSWORD="iforgot"
MY_IP="192.168.49.245"

MY_MASTER_USER="root"
MY_MASTER_PASSWORD=""
MY_MASTER_IP="192.168.101.137"

#=======================================================================
#备份保存天数，即删除N天之前的备份
#=======================================================================
DELETE_DAYS=7

#=======================================================================
#binlog目录
#=======================================================================
BINLOG_FILE=/r2/mysqldata

#=======================================================================
#备份目录
#=======================================================================
BASE_DIR=/mybak
FULL_BASE_DIR=${BASE_DIR}/full
INCR_BASE_DIR=${BASE_DIR}/incr
FULL_BACKUP_DIR=${FULL_BASE_DIR}/full_${DATE}
INCR_BACKUP_DIR=${INCR_BASE_DIR}/incr_${DATE2}

#=======================================================================
#mysql和mysqldump相关选项
#=======================================================================

MYSQL_CONN_OPTION=" -u$MY_USER -p$MY_PASSWORD -h$MY_IP"
MYSQLDUMP_OPTION=" --single-transaction --master-data=2 --flush-logs -E -R --databases"
FILTER="information_schema|test|sys|performance_schema"
MYSQL_MASTER_CONN_OPTION=" -u$MY_MASTER_USER -p$MY_MASTER_PASSWORD -h$MY_MASTER_IP"

#=======================================================================
#日志文件
#=======================================================================
PUBLIC_LOG=$BASE_DIR/public_backup.log
PUBLIC_POSITION=$BASE_DIR/public_position
FULL_LOG=$FULL_BACKUP_DIR/backup_full.log
INCR_LOG=$INCR_BACKUP_DIR/backup_incr.log
SCHEMA_NAME_FILE=$FULL_BACKUP_DIR/dbname
#=======================================================================
#判断帐号和IP是否异常
#=======================================================================

mysql $MYSQL_CONN_OPTION  -e 'select @@hostname as  Backup_Host;'
if [ "$?" -ne 0 ];then
    echo -e "Backup_Host连接异常,请检查帐号密码和主机名/IP......"  >$PUBLIC_LOG
    echo -e "Backup_Host连接异常,请检查帐号密码和主机名/IP......"
    exit 1
  else
    echo -e "Backup_Host 连接正常"
    echo -e "Backup_Host 连接正常" >$PUBLIC_LOG
fi

#=======================================================================
#创建备份目录
#=======================================================================
if [ ! -d "${BASE_DIR}" ];then
        echo "创建BASE_DIR目录"
        mkdir -p $BASE_DIR
        echo $BASE_DIR && cd $BASE_DIR
fi

#=======================================================================
#MySQL备份（函数）
#=======================================================================

function backup(){
        START_TIME=`date +%Y%m%d\ %H:%M:%S`
            echo -e "1、$START_TIME 开始备份...... "
            echo -e "1、$START_TIME 开始备份...... " > $FULL_LOG
        #1.获取逻辑数据库名
         mysql $MYSQL_CONN_OPTION -Bse 'show databases' | grep -iwvE $FILTER | tr "\n" " "  > $SCHEMA_NAME_FILE
         SCHEMA_NAME=`cat $SCHEMA_NAME_FILE`
        #2.开始备份
            echo -e "2、备份以下数据库：\n $SCHEMA_NAME"
            echo -e "2、备份以下数据库：\n $SCHEMA_NAME" >> $FULL_LOG
        mysqldump $MYSQL_CONN_OPTION  $MYSQLDUMP_OPTION $SCHEMA_NAME |gzip >$FULL_BACKUP_DIR/fullbak.sql.gz
        #if [ "${PIPESTATUS[0]}" -eq 0 ];then
        if [ "${PIPESTATUS[0]}" -eq 0 ];then
            DONE_TIME=`date +%Y%m%d\ %H:%M:%S`
            echo "3、$DONE_TIME 备份成功......"
            echo "3、$DONE_TIME 备份成功......" >>$FULL_LOG
            #备份完成后计算时
            SPEND_TIME=$(($(date +%s -d "$DONE_TIME")-$(date +%s -d "$START_TIME")))
            echo "4、备份用时: ${SPEND_TIME} 秒"
            echo "4、备份用时: ${SPEND_TIME} 秒" >> $FULL_LOG
        else
            DONE_TIME=`date +%Y%m%d\ %H:%M:%S`
            echo -e "3、$DONE_TIME备份异常结束."  >>$FULL_LOG
            echo -e "3、$DONE_TIME备份异常结束."
            echo -e "请检查mysqldump和grep参数"  >>$FULL_LOG
            echo -e "请检查mysqldump和grep参数."
            return 1
        fi
        # 3.备份文件夹大小
        DATA=`du -sh $FULL_BACKUP_DIR |awk '{print $1}'`
        echo "5、备份数据量大小: $DATA " >> $FULL_LOG
        echo "5、备份数据量大小: $DATA "
        # 获取GTID和postion点
        sleep 5s
        gunzip <$FULL_BACKUP_DIR/fullbak.sql.gz |sed -n '1,50p'| grep -E "MASTER|GTID" > $FULL_BACKUP_DIR/position
        # 写入最后的binlog名到公共文件中
        cat $FULL_BACKUP_DIR/position |grep -iwE MASTER_LOG_FILE |awk -F "'" '{print $2}' > $PUBLIC_POSITION

        #记录最新的binlog文件名
        echo "6、记录最新的binlog文件名!" >> $FULL_LOG
        echo "6、记录最新的binlog文件名!"
        cat $PUBLIC_POSITION >> $FULL_LOG
}
#=======================================================================
# 导出用户权限设置 （函数）
#=======================================================================
function exp_grants(){
    mysql $MYSQL_CONN_OPTION -B -N $@ -e "SELECT CONCAT('SHOW GRANTS FOR ''', user, '''@''', host, ''';') AS query FROM mysql.user" | mysql $MYSQL_CONN_OPTION $@ | sed 's/\(GRANT .*\)/\1;/;s/^\(Grants for .*\)/-- \1 /;/--/{x;p;x;}'
}
#=======================================================================
# 导出用户帐号 （函数）
#=======================================================================
function exp_users(){
    mysql $MYSQL_CONN_OPTION -B -N $@ -e "SELECT CONCAT('SHOW CREATE USER ''', user, '''@''', host, ''';') AS query FROM mysql.user" | mysql $MYSQL_CONN_OPTION $@ | sed 's/\(CREATE .*\)/\1;/;s/^\(CREATE USER for .*\)/-- \1 /;/--/{x;p;x;}'
}

#=======================================================================
# 导出master用户权限设置 （函数）
#=======================================================================
function exp_master_grants(){
    mysql $MYSQL_MASTER_CONN_OPTION -B -N $@ -e "SELECT CONCAT('SHOW GRANTS FOR ''', user, '''@''', host, ''';') AS query FROM mysql.user" | mysql $MYSQL_MASTER_CONN_OPTION $@ | sed 's/\(GRANT .*\)/\1;/;s/^\(Grants for .*\)/-- \1 /;/--/{x;p;x;}'
}
#=======================================================================
# 导出master用户帐号 （函数）
#=======================================================================
function exp_master_users(){
    mysql $MYSQL_MASTER_CONN_OPTION -B -N $@ -e "SELECT CONCAT('SHOW CREATE USER ''', user, '''@''', host, ''';') AS query FROM mysql.user" | mysql $MYSQL_MASTER_CONN_OPTION $@ | sed 's/\(CREATE .*\)/\1;/;s/^\(CREATE USER for .*\)/-- \1 /;/--/{x;p;x;}'
}


#=======================================================================
# 全备导出用户帐号和权限信息
#=======================================================================
function exp_user_info()
{

mysql $MYSQL_CONN_OPTION  -e 'select @@hostname as MY_Host;'
if [ $? -eq 0 ];then
     echo -e "$MY_IP开始导出帐号和权限信息" >>$FULL_LOG
     echo -e "$MY_IP开始导出帐号和权限信息"
    VERSTON=`mysql $MYSQL_CONN_OPTION  -Bse "select @@version" |cut -b 1-3`
    if [ $VERSTON = "5.7" ];then
        exp_grants > $FULL_BACKUP_DIR/grants.sql
        GRANTS=`grep -iwE "Grants" $FULL_BACKUP_DIR/grants.sql |wc -l`
        if [ $GRANTS -gt 0 ];then
          echo -e "$MY_IP成功导出 $GRANTS 个用户权限" >>$FULL_LOG
          echo -e "$MY_IP成功导出 $GRANTS 个用户权限"
        else
          echo -e "$MY_IP导出用户帐号异常结束."  >>$FULL_LOG
          echo -e "$MY_IP导出用户帐号异常结束."
          echo -e "$MY_IP请检查帐号权限."  >>$FULL_LOG
          echo -e "$MY_IP请检查帐号权限."
          return 1
        fi
        exp_users > $FULL_BACKUP_DIR/users.sql
        USERS=`grep -iwE "IDENTIFIED" $FULL_BACKUP_DIR/users.sql |wc -l`
        if [ $USERS -gt 0 ];then
          echo -e "$MY_IP成功导出 $USERS 个用户帐号" >>$FULL_LOG
          echo -e "$MY_IP成功导出 $USERS 个用户帐号"
        else
          echo -e "$MY_IP导出用户帐号异常结束."  >>$FULL_LOG
          echo -e "$MY_IP导出用户帐号异常结束."
          echo -e "$MY_IP请检查帐号权限."  >>$FULL_LOG
          echo -e "$MY_IP请检查帐号权限."
          return 1
        fi
    else
        exp_grants > $FULL_BACKUP_DIR/grants.sql
        GRANTS=`grep -iwE "Grants" $FULL_BACKUP_DIR/grants.sql |wc -l`
        if [ $GRANTS -gt 0 ];then
          echo -e "$MY_IP成功导出 $GRANTS 个用户权限" >>$FULL_LOG
          echo -e "$MY_IP成功导出 $GRANTS 个用户权限"
        else
          echo -e "$MY_IP导出用户帐号异常结束."  >>$FULL_LOG
          echo -e "$MY_IP导出用户帐号异常结束."
          echo -e "$MY_IP请检查帐号权限."  >>$FULL_LOG
          echo -e "$MY_IP请检查帐号权限."
          return 1
        fi
    fi
else
    echo -e "$MY_IP连接异常,请检查帐号密码和主机名/IP......"  >>$FULL_LOG
    echo -e "$MY_IP连接异常,请检查帐号密码和主机名/IP......"
    return 1
fi
}
#=======================================================================
# 全备导出master用户帐号和权限信息
#=======================================================================

function exp_master_user_info()
{
mysql $MYSQL_MASTER_CONN_OPTION  -e 'select @@hostname as Master_Host;'
if [ $? -eq 0 ];then
     echo -e "master $MY_MASTER_IP开始导出帐号和权限信息" >>$FULL_LOG
     echo -e "master $MY_MASTER_IP开始导出帐号和权限信息"
    VERSTON=`mysql $MYSQL_MASTER_CONN_OPTION  -Bse "select @@version" |cut -b 1-3`
    if [ $VERSTON = "5.7" ];then
        exp_master_grants > $FULL_BACKUP_DIR/master_grants.sql
        GRANTS=`grep -iwE "Grants" $FULL_BACKUP_DIR/master_grants.sql |wc -l`
        if [ $GRANTS -gt 0 ];then
          echo -e "master $MY_MASTER_IP成功导出 $GRANTS 个用户权限" >>$FULL_LOG
          echo -e "master $MY_MASTER_IP成功导出 $GRANTS 个用户权限"
        else
          echo -e "master $MY_MASTER_IP导出用户帐号异常结束."  >>$FULL_LOG
          echo -e "master $MY_MASTER_IP导出用户帐号异常结束."
          echo -e "master $MY_MASTER_IP请检查帐号权限."  >>$FULL_LOG
          echo -e "master $MY_MASTER_IP请检查帐号权限."
          return 
        fi
        exp_master_users > $FULL_BACKUP_DIR/master_users.sql
        USERS=`grep -iwE "IDENTIFIED" $FULL_BACKUP_DIR/master_users.sql |wc -l`
        if [ $USERS -gt 0 ];then
          echo -e "master $MY_MASTER_IP成功导出 $USERS 个用户帐号" >>$FULL_LOG
          echo -e "master $MY_MASTER_IP成功导出 $USERS 个用户帐号"
        else
          echo -e "master $MY_MASTER_IP导出用户帐号异常结束."  >>$FULL_LOG
          echo -e "master $MY_MASTER_IP导出用户帐号异常结束."
          echo -e "master $MY_MASTER_IP请检查帐号权限."  >>$FULL_LOG
          echo -e "master $MY_MASTER_IP请检查帐号权限."
          return 
        fi
    else
        exp_master_grants > $FULL_BACKUP_DIR/master_grants.sql
        GRANTS=`grep -iwE "Grants" $FULL_BACKUP_DIR/master_grants.sql |wc -l`
        if [ $GRANTS -gt 0 ];then
          echo -e "master $MY_MASTER_IP成功导出 $GRANTS 个用户权限" >>$FULL_LOG
          echo -e "master $MY_MASTER_IP成功导出 $GRANTS 个用户权限"
        else
          echo -e "master $MY_MASTER_IP导出用户帐号异常结束."  >>$FULL_LOG
          echo -e "master $MY_MASTER_IP导出用户帐号异常结束."
          echo -e "master $MY_MASTER_IP请检查帐号权限."  >>$FULL_LOG
          echo -e "master $MY_MASTER_IP请检查帐号权限."
          return 
        fi
    fi
else
    echo -e "master $MY_MASTER_IP连接异常,请检查帐号密码和主机名/IP......"  >>$FULL_LOG
    echo -e "master $MY_MASTER_IP连接异常,请检查帐号密码和主机名/IP......"
    return 
fi
}

#=======================================================================
# 只导出master用户帐号和权限信息
#=======================================================================

function only_exp_master_user()
{
mysql $MYSQL_MASTER_CONN_OPTION  -e 'select @@hostname as Master_Host;'
if [ $? -eq 0 ];then
     echo -e "master $MY_MASTER_IP开始导出帐号和权限信息" >>$PUBLIC_LOG
     echo -e "master $MY_MASTER_IP开始导出帐号和权限信息"
    VERSTON=`mysql $MYSQL_MASTER_CONN_OPTION  -Bse "select @@version" |cut -b 1-3`
    if [ $VERSTON = "5.7" ];then
        exp_master_grants > $BASE_DIR/master_grants.sql
        GRANTS=`grep -iwE "Grants" $BASE_DIR/master_grants.sql |wc -l`
        if [ $GRANTS -gt 0 ];then
          echo -e "master $MY_MASTER_IP成功导出 $GRANTS 个用户权限" >>$PUBLIC_LOG
          echo -e "master $MY_MASTER_IP成功导出 $GRANTS 个用户权限"
        else
          echo -e "master $MY_MASTER_IP导出用户帐号异常结束."  >>$PUBLIC_LOG
          echo -e "master $MY_MASTER_IP导出用户帐号异常结束."
          echo -e "master $MY_MASTER_IP请检查帐号权限."  >>$PUBLIC_LOG
          echo -e "master $MY_MASTER_IP请检查帐号权限."
          return 1
        fi
        exp_master_users > $BASE_DIR/master_users.sql
        USERS=`grep -iwE "IDENTIFIED" $BASE_DIR/master_users.sql |wc -l`
        if [ $USERS -gt 0 ];then
          echo -e "master $MY_MASTER_IP成功导出 $USERS 个用户帐号" >>$PUBLIC_LOG
          echo -e "master $MY_MASTER_IP成功导出 $USERS 个用户帐号"
        else
          echo -e "master $MY_MASTER_IP导出用户帐号异常结束."  >>$PUBLIC_LOG
          echo -e "master $MY_MASTER_IP导出用户帐号异常结束."
          echo -e "master $MY_MASTER_IP请检查帐号权限."  >>$PUBLIC_LOG
          echo -e "master $MY_MASTER_IP请检查帐号权限."
          return 1
        fi
    else
        exp_master_grants > $BASE_DIR/master_grants.sql
        GRANTS=`grep -iwE "Grants" $BASE_DIR/master_grants.sql |wc -l`
        if [ $GRANTS -gt 0 ];then
          echo -e "master $MY_MASTER_IP成功导出 $GRANTS 个用户权限" >>$PUBLIC_LOG
          echo -e "master $MY_MASTER_IP成功导出 $GRANTS 个用户权限"
        else
          echo -e "master $MY_MASTER_IP导出用户帐号异常结束."  >>$PUBLIC_LOG
          echo -e "master $MY_MASTER_IP导出用户帐号异常结束."
          echo -e "master $MY_MASTER_IP请检查帐号权限."  >>$PUBLIC_LOG
          echo -e "master $MY_MASTER_IP请检查帐号权限."
          return 1
        fi
    fi
else
    echo -e "master $MY_MASTER_IP连接异常,请检查帐号密码和主机名/IP......"  >>$PUBLIC_LOG
    echo -e "master $MY_MASTER_IP连接异常,请检查帐号密码和主机名/IP......"
    return 1
fi
}

#=======================================================================
# 全备：判断MySQL版本，导出帐号和权限信息并执行备份，使用gzip压缩
#=======================================================================
function main_full_backup()
{

if [ ! -d "${FULL_BACKUP_DIR}" ];then
        echo "创建FULL_BACKUP_DIR目录"
        mkdir -p $FULL_BACKUP_DIR
        echo $FULL_BACKUP_DIR && cd $FULL_BACKUP_DIR
fi

if [ ! -f "$FULL_LOG" ]; then
        echo -e "$FULL_LOG 不存在，重新创建. "
        echo -e "$FULL_LOG 不存在，重新创建. " >> $PUBLIC_LOG
        touch "$INCR_LOG"
fi


#导出本机帐号信息
exp_user_info
#执行备份
backup
#导出master帐号信息
exp_master_user_info
}

#=======================================================================
# 增量：使用mysqlbinlog导出binlog生成sql，使用gzip压缩
#=======================================================================

function main_incr_bakcup()
{
#判断文件是否创建
if [ ! -d "${INCR_BACKUP_DIR}" ];then
        echo "创建INCR_BACKUP_DIR目录"
        mkdir -p $INCR_BACKUP_DIR
        echo $INCR_BACKUP_DIR && cd $INCR_BACKUP_DIR
fi

if [ ! -f "$INCR_LOG" ]; then
        echo -e "创建 $INCR_LOG "
        echo -e "创建 $INCR_LOG " >> $PUBLIC_LOG
        touch "$INCR_LOG"
fi

if [ ! -d $BINLOG_FILE ]; then
    echo -e "$BINLOG_FILE 不存在，请配置正确的路径. "
    echo -e "$BINLOG_FILE 不存在，请配置正确的路径. " >> $INCR_LOG
    exit
fi

OLD_BINLOGS=$INCR_BACKUP_DIR/old_binlogs_list
if [ ! -f "$OLD_BINLOGS" ]; then
    touch "$OLD_BINLOGS"
fi

NEW_BINLOGS=$INCR_BACKUP_DIR/new_binlogs_list
if [ ! -f "$NEW_BINLOGS" ]; then
    touch "$NEW_BINLOGS"
fi

TMP_BINLOG_NAME=$INCR_BACKUP_DIR/tmp_binlog_name
if [ ! -f "$TMP_BINLOG_NAME" ]; then
    touch "$TMP_BINLOG_NAME"
fi

#在刷新之前把binary logs 列表写入old_binlogs
mysql $MYSQL_CONN_OPTION  -Bse 'show binary logs' |awk '{print $1}' > $OLD_BINLOGS

#刷新产生新的binlog文件
mysqladmin  $MYSQL_CONN_OPTION  flush-logs

#在刷新之前把binary logs 列表后入new_binlogs
mysql $MYSQL_CONN_OPTION  -Bse 'show binary logs' |awk '{print $1}' > $NEW_BINLOGS

#截取上一次备份的binlog名的后面数字
OLD_NUM=`cat $PUBLIC_POSITION |awk -F "." '{print $NF}'`

#判断OLD_NUM有没有获取到数值，没有执行全备
if [ $OLD_NUM ]
then
   echo "$OLD_NUM : PUBLIC_POSITION 有获取到数值"
else
   echo "OLD_NUM : PUBLIC_POSITION 没有获取到数值,执行全备"
   echo "OLD_NUM : PUBLIC_POSITION 没有获取到数值,执行全备" >>$PUBLIC_LOG
   main_full_backup
   echo "全备执行成功"
   echo "全备执行成功" >> $PUBLIC_LOG
   #跳回函数run下面的incr BACKUP_OK
   return 1
fi

#截取刷新后的binlog名的后面数字
NEW_NUM=`tail -1 $NEW_BINLOGS |awk -F "." '{print $NF}'`

#读取old_binlogs_list，循环截取binlog后面数字，再与OLD_NUM和NEW_NUM比对
for TMP_BINGLOG_NUWS in `cat $OLD_BINLOGS |awk -F "." '{print $NF}'`
do
    if [ ${TMP_BINGLOG_NUWS} -lt ${NEW_NUM} -a ${TMP_BINGLOG_NUWS} -ge ${OLD_NUM} ]
    then
        echo -e "需备份后缀为 $TMP_BINGLOG_NUWS binlog文件" >> $INCR_LOG
        cat $OLD_BINLOGS |grep $TMP_BINGLOG_NUWS >> $TMP_BINLOG_NAME
    else
        echo "不需要备份，后缀为 $TMP_BINGLOG_NUWS binlog文件" >> $INCR_LOG
    fi
done
if [ $? -eq 0 ];then
  echo -e "循环写入binlog名执行成功"
else
  echo -e "循环写入binlog名异常，退出增量备份"  >> $INCR_LOG
  echo -e "循环写入binlog名异常，退出增量备份"
  return 1
fi


#判断TMP_BINLOG_NAME是否为空

if [ -s $TMP_BINLOG_NAME ]
then
    cd $BINLOG_FILE
    mysqlbinlog -vv `cat $TMP_BINLOG_NAME |tr "\n" " "` |gzip > $INCR_BACKUP_DIR/incr.sql.gz
    if [ "${PIPESTATUS[0]}" -eq 0 ];then
      echo "mysqlbinlog 执行成功......"
      echo "mysqlbinlog 执行成功......" >> $INCR_LOG
      # 写入最后的binlog名到公共文件中
      tail -1 $NEW_BINLOGS > $PUBLIC_POSITION
      if [ $? -eq 0 ];then
        echo -e "写入最新的binlog名到公共文件中"
      else
        echo -e "写入binlog名到公共文件中失败，请排查并重新执行增量备份"  >> $INCR_LOG
        echo -e "写入binlog名到公共文件中失败，请排查并重新执行增量备份"
        return 1
      fi
        echo "incr_bakcup_ok" >> $PUBLIC_LOG
    else
      echo -e "mysqlbinlog导出binlog异常结束......"  >> $INCR_LOG
      echo -e "mysqlbinlog导出binlog异常结束......"
      echo -e "请检查mysqlbinlog参数和$TMP_BINLOG_NAME文件"  >> $INCR_LOG
      echo -e "请检查mysqlbinlog参数和$TMP_BINLOG_NAME文件"
      return 1
    fi
else
  echo -e "TMP_BINLOG_NAME为空，退出增量备份"  >> $INCR_LOG
  echo -e "TMP_BINLOG_NAME为空，退出增量备份"
  return 1
fi
}

#=======================================================================
# usage 使用帮助
#=======================================================================
function usage()
{
echo "+-----------------------------------------------------------------------------+"
echo "|Usage : ./bak_mysql.sh  (full|incr|oemu)                                     |"
echo "+-----------------------------------------------------------------------------+"
echo "|全备              ：./bak_mysql.sh full                                      |"
echo "|增量              ：./bak_mysql.sh incr                                      |"
echo "|只导出master权限  ：./bak_mysql.sh oemu                                      |"
echo "+-----------------------------------------------------------------------------+"
echo "计划任务参考"
echo "+-----------------------------------------------------------------------------+"
echo "|全备  ：30 0 * * *  /bin/sh  /scripts/bak_mysql.sh full >/dev/null 2>&1      |"
echo "|增量  ：30 2-23/2 * * *  /bin/sh  /scripts/bak_mysql.sh incr >/dev/null 2>&1 |"
echo "+-----------------------------------------------------------------------------+"
exit 1
}

#=======================================================================
#  选择执行备份
#=======================================================================

run()
{
BACKUP_TYPE=$1
case $BACKUP_TYPE in
 full)
    # 全量备份
    main_full_backup
    BACKUP_OK=$?
    if [ 0 -eq "$BACKUP_OK" ]; then
      # 全备成功
      echo -e "全备成功"  >> $PUBLIC_LOG
      echo -e "全备成功"
      # 删除N天之前的数据
      find $FULL_BASE_DIR  -mtime +$DELETE_DAYS  -type d -name "full*" -exec rm -rf {} \;
      echo "删除 $FULL_BASE_DIR 目录下 $DELETE_DAYS 天之前的备份!" >> $PUBLIC_LOG
      echo "删除 $FULL_BASE_DIR 目录下 $DELETE_DAYS 天之前的备份!" 
      echo "full_bakcup_ok" >> $PUBLIC_LOG
    else
      # 全备失败
      echo -e "全备失败"  >> $PUBLIC_LOG
      echo -e "全备失败"
      # 删除备份目录
      if [  -d "$FULL_BACKUP_DIR" ]; then
        rm -rf $FULL_BACKUP_DIR
        echo -e "全备失败,删除备份目录"  >> $PUBLIC_LOG
        echo -e "全备失败,删除备份目录"
      fi
    fi
    ;;
  incr)
    # 增量备份
    main_incr_bakcup
    BACKUP_OK=$?
    if [ 0 -eq "$BACKUP_OK" ]; then
      # 增量备份成功
      echo -e "增量备份成功"  >> $PUBLIC_LOG
      echo -e "增量备份成功"
      # 删除N天之前的数据
      find $INCR_BASE_DIR  -mtime +$DELETE_DAYS  -type d -name "incr*" -exec rm -rf {} \;
      echo "删除 $INCR_BASE_DIR 目录下 $DELETE_DAYS 天之前的备份!" >> $PUBLIC_LOG
      echo "删除 $INCR_BASE_DIR 目录下 $DELETE_DAYS 天之前的备份!"
    else
      # 增量备份失败
      echo -e "增量备份失败"  >> $PUBLIC_LOG
      echo -e "增量备份失败"
      # 删除备份目录
      if [  -d "$INCR_BACKUP_DIR" ]; then
        rm -rf $INCR_BACKUP_DIR
        echo -e "增量失败,删除备份目录"  >> $PUBLIC_LOG
        echo -e "增量失败,删除备份目录"
      fi
    fi
    ;;

  oemu)
    #导出master帐号信息
    only_exp_master_user
    BACKUP_OK=$?
    if [ 0 -eq "$BACKUP_OK" ]; then
      # master用户帐号和权限备份成功
      echo -e "master $MY_MASTER_IP导出用户帐号和权限成功"  >> $PUBLIC_LOG
      echo -e "master $MY_MASTER_IP导出用户帐号和权限成功"
    else
      # master用户帐号和权限备份失败
      echo -e "master $MY_MASTER_IP导出用户帐号和权限失败"  >> $PUBLIC_LOG
      echo -e "master $MY_MASTER_IP导出用户帐号和权限失败"
    fi
    ;;
 *)
      echo "+------------------------------+"
      echo "+--脚本参数错误，请参考usage---+"
      echo "+------------------------------+"
      usage
      ;;
esac
}
run $1
