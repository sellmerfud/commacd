# shellcheck shell=bash disable=2288  # Ignore warning about command with name (,)
shopt -s expand_aliases
. commacd.sh

ROOT=/tmp/commacd.shpec
rm -rf $ROOT
mkdir -p $ROOT/projects/{jekyll/node_modules/tj/src,ghost,mysql-binlog-connector-java/src/main/java,mappify/{.git,src/test}}
mkdir -p $ROOT/space\ hell/{a\ a,b\ b,a\ b}

COMMACD_CD="cd" # supress pwd

describe 'commacd'

  describe ','
    it 'does nothing in case of no arguments'
      cd $ROOT || return 1
      ,
      assert equal "$PWD" $ROOT
    end
    it 'stays in the same directory in case of no match'
      cd $ROOT || return 1
      , p/nonexisting
      assert equal "$PWD" $ROOT
    end
    it 'changes directory without asking anything in case of single (unique) match'
      cd $ROOT || return 1
      , p/m/s/m
      assert equal "$PWD" "$ROOT/projects/mysql-binlog-connector-java/src/main"
    end
    it 'supports patterns starting with /'
      cd $ROOT || return 1
      , $ROOT/p/j
      assert equal "$PWD" "$ROOT/projects/jekyll"
    end
    it 'asks for user input in case of multiple choices'
      cd $ROOT || return 1
      , $ROOT/p/m 2> /dev/null <<< $(echo 0)
      assert equal "$PWD" "$ROOT/projects/mappify"
    end
    it 'can be used in subshells'
      cd $ROOT || return 1
      commacd_to_restore=$COMMACD_CD
      COMMACD_CD=
      v=$(, p)
      COMMACD_CD=$commacd_to_restore
      assert equal "$v" "$ROOT/projects"
    end
    it 'does not break on spaces'
      cd $ROOT || return 1
      , s/b
      assert equal "$PWD" "$ROOT/space hell/b b"
    end
    it ', switches to fuzzy mode when there are no matches by prefix'
      cd $ROOT/projects || return 1
      , binlog
      assert equal "$PWD" "$ROOT/projects/mysql-binlog-connector-java"
    end
    it ', switches to fuzzy mode when there are no matches by prefix containing /'
      cd $ROOT || return 1
      , p/binlog
      assert equal "$PWD" "$ROOT/projects/mysql-binlog-connector-java"
    end
  end

  describe ',,'
    it 'goes to the project root directory in case of no arguments'
      cd $ROOT/projects/mappify/src/test || return 1
      ,,
      assert equal "$PWD" "$ROOT/projects/mappify"
    end
    it 'stays in the same directory in case of no match'
      cd $ROOT || return 1
      ,,
      ,, nonexisting
      assert equal "$PWD" $ROOT
    end
    it 'always switches to the closest match'
      cd $ROOT/projects/mysql-binlog-connector-java/src/main/java || return 1
      ,, m
      assert equal "$PWD" "$ROOT/projects/mysql-binlog-connector-java/src/main"
    end
    it 'performs substitution in case of two arguments'
      cd $ROOT/projects/jekyll || return 1
      ,, jekyll ghost
      assert equal "$PWD" $ROOT/projects/ghost
    end
    it 'supports patterns starting with /'
      cd $ROOT/projects/mappify/src/test || return 1
      ,, $ROOT/projects/mappify
      assert equal "$PWD" "$ROOT/projects/mappify"
    end
    it 'can be used in subshells'
      cd $ROOT/projects/jekyll || return 1
      commacd_to_restore=$COMMACD_CD
      COMMACD_CD=
      v=$(,, pro)
      COMMACD_CD=$commacd_to_restore
      assert equal "$v" "$ROOT/projects"
    end
    it 'does not break on spaces'
      cd "$ROOT/space hell/b b" || return 1
      ,, s
      assert equal "$PWD" "$ROOT/space hell"
    end
    it ',, switches to fuzzy mode when there are no matches by prefix'
      cd $ROOT/projects/mysql-binlog-connector-java/src/main/java || return 1
      ,, binlog
      assert equal "$PWD" "$ROOT/projects/mysql-binlog-connector-java"
    end
    it ',, switches to fuzzy mode only after full path scan'
      cd $ROOT/projects/jekyll/node_modules/tj/src || return 1
      ,, j
      assert equal "$PWD" "$ROOT/projects/jekyll"
    end
  end

  describe ',,,'
     it 'does nothing in case of no arguments'
      cd $ROOT || return 1
      ,,,
      assert equal "$PWD" $ROOT
    end
    it 'stays in the same directory in case of no match'
      cd $ROOT || return 1
      ,,, nonexisting
      assert equal "$PWD" $ROOT
    end
    it 'changes directory without asking anything in case of single (unique) match'
      cd $ROOT/projects/mappify/src/test || return 1
      ,,, mysql
      assert equal "$PWD" "$ROOT/projects/mysql-binlog-connector-java"
    end
    it 'supports patterns starting with /'
      cd $ROOT/projects/mappify || return 1
      ,,, $ROOT/projects/mysql
      assert equal "$PWD" "$ROOT/projects/mysql-binlog-connector-java"
    end
    it 'asks for user input in case of multiple choices'
      cd $ROOT/projects/jekyll || return 1
      ,,, m 2> /dev/null <<< $(echo 0)
      assert equal "$PWD" "$ROOT/projects/mappify"
    end
    it 'can be used in subshells'
      cd $ROOT/projects/jekyll || return 1
      commacd_to_restore=$COMMACD_CD
      COMMACD_CD=
      v=$(,,, mysql)
      COMMACD_CD=$commacd_to_restore
      assert equal "$v" "$ROOT/projects/mysql-binlog-connector-java"
    end
    it 'does not break on spaces'
      cd "$ROOT/space hell/a a" || return 1
      ,,, b
      assert equal "$PWD" "$ROOT/space hell/b b"
    end
    it ',,, switches to fuzzy mode when there are no matches by prefix'
      cd $ROOT/projects/mappify || return 1
      ,,, binlog
      assert equal "$PWD" "$ROOT/projects/mysql-binlog-connector-java"
    end
  end

end
