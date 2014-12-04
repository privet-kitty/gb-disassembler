;;;;逆アセンブラ
;後はデータ部を考慮する部分を作れば終わり...と思ってたら、
;どうやらCB groupの命令はカスタムCPUでも残っているらしい。
;根本的な誤りを犯してしまった.....(8/17に修正)
;

;;指定の桁数で16進数表示する。digitは自然数
;(defun prinhex (num digit)
;  (if (zerop num)
;      (dotimes (x digit) (princ 0))
;      (do ((d (expt #x10 (- digit 1)) (/ d #x10)))
;	  ((>= num d) (format t "~x" num))
;	(princ 0))))


(defpackage #:z80disas (:use :sb-ext :common-lisp))
(in-package z80disas)

(export 'disassemble-file)

;都合上マクロで書いてみる。
;でも、こういうのにexptや除算を使うってのは素朴すぎ(遅すぎ)では
;numは整数
;format ~,num'0Dでも同様のことができるが、負数の場合の出力がショボい

(defmacro prinhex (num digit &optional (str t) (sign nil))
  (let ((_num (gensym))
	(_digit (gensym))
	(_str (gensym))
	(_sign (gensym))
	(x (gensym))
	(d (gensym)))
    `(let ((,_num ,num)
	   (,_digit ,digit)
	   (,_str ,str)
	   (,_sign ,sign))
       (if (zerop ,_num)
	   (progn
	     (when ,_sign (princ #\+ ,_str))
	     (dotimes (,x ,_digit) (princ 0 ,_str)))
	   (progn
	     (if (< ,_num 0)
		 (princ #\- ,_str)
		 (when ,_sign (princ #\+ ,_str)))
	     (let ((,_num (abs ,_num)))
	       (do ((,d (expt #x10 (- ,_digit 1)) (/ ,d #x10)))
		   ((>= ,_num ,d) (format ,_str "~x" ,_num))
		 (princ 0 ,_str))))))))

;ubyteからsigned byteへの変換
;(defun unsigned-byte-to-signed-byte (ubyte)
;  (unless (and (typep ubyte 'fixnum)
;	       (<= 0 ubyte)
;	       (<= ubyte #xFF))
;    (error "unsigned-byte-to-signed:ubyte must be integer 0 to 255"))
;  (if (< ubyte 128)
;      ubyte
;      (- ubyte 256)))

;エラーチェック無しのバージョン
(defun unsigned-byte-to-signed-byte (ubyte)
  (declare (unsigned-byte ubyte))
  (if (zerop (logand ubyte #b10000000))
      ubyte
      (- ubyte 256)))


;reg;reg_to_mem;8bitnum;16bitnum;16bitnum_to_mem;relative8bitnum

;mnは表示するmnemonic
;print-mnemonicは#x4000とか次のデータの開始位置は気にしないので、
;呼び出す側で配慮する必要がある
(defun print-mnemonic (mn bins point ostr)
  (if (mn-special mn)
      (funcall (mn-special mn) bins point ostr)
      (progn
	(format ostr "~a  " (mn-opcode mn))
	(pmn (mn-type mn) (mn-operand mn) (cdr bins) point ostr))))

(defun pmn (optype operand bins point ostr)
  (cond ((null optype) nil)
	(t (let ((opt (car optype)))
	     (cond ((eql opt 'reg)
		    (format ostr "~a" (car operand))
		    (when (cdr optype) (princ #\, ostr))
		    (pmn (cdr optype) (cdr operand) bins point ostr)) ;r
		   ((eql opt 'reg_to_mem)
		    (format ostr "(~a)" (car operand))
		    (when (cdr optype) (princ #\, ostr))
		    (pmn (cdr optype) (cdr operand) bins point ostr)) ;(r)
		   ((eql opt '8bitnum)
		    (prinhex (car bins) 2 ostr)
		    (when (cdr optype) (princ #\, ostr))
		    (pmn (cdr optype) operand (cdr bins) point ostr)) ;n
		   ((eql opt '16bitnum)
		    (format ostr "~2,'0x~2,'0x" (second bins) (first bins))
		    (when (cdr optype) (princ #\, ostr))
		    (pmn (cdr optype) operand (cddr bins) point ostr)) ;nn
		   ((eql opt '16bitnum_to_mem)
		    (format ostr "(~2,'0x~2,'0x)" (second bins) (first bins))
		    (when (cdr optype) (princ #\, ostr))
		    (pmn (cdr optype) operand (cddr bins) point ostr)) ;(nn)
		   ((eql opt 'relative8bitnum)
		    (prinhex (unsigned-byte-to-signed-byte (car bins)) 2 ostr)
		    (when (cdr optype) (princ #\, ostr))
		    (pmn (cdr optype) operand (cdr bins) point ostr))
		   (t (error "不明なタイプが混じっています in pmn")))))))
		    


;bin-strをstartからendまで空読みする
(defun empty-read (bin-str start end)
  (do ((s start (+ s 1)))
      ((= s end))
    (read-byte bin-str)))


;データ部分の出力
(defun read-data (bin-str start end bank ostr &key (caption ""))
  (format ostr "==data:~a==~%" caption)
  (do ((row (- start (mod start #x10)) (+ row #x10)))
      ((>= row end))
    (let ((row-end (+ row #x10)))
      (format ostr "~2,'0x:~4,'0x " bank row) ;"01:20ff "などと"バンク:行 "の出力をする
      (do ((x row (+ x 1)))
	  ((= x row-end))
	(cond ((< x start) (princ "**" ostr))
	      ((>= x end) (princ "**" ostr))
	      (t (prinhex (read-byte bin-str) 2 ostr)))
	(princ #\  ostr))
      (terpri ostr)))
  (terpri ostr))


;'(#x01 #xEF #x32)みたいな数リストを返す
;途中でendに達すると、nilを返す
;ファイルの終端に達したときもnilを返す
;第2値にpointの位置を返す
(defconstant CBxx 1)

(defun read-bins-and-display (bin-str point end bank ostr &optional (mbytesop 0))
  (let ((x (read-byte bin-str nil)))
    (if (null x)			;終端に達したらこの時点で戻る
	(values nil point)
	(progn
	  (when (zerop mbytesop)
	    (format ostr "~2,'0x:~4,'0x ~2,'0x " bank point x)) ;"バンク:行 最初の数値 "の出力をする
	  (cond ((= mbytesop CBxx)
		 (let* ((len (mn-len (svref *optable-cb* x)))
			(point+len (+ point len)))
		   (cond ((> point+len end) ;現在地+命令長がendを越える場合
			  (let ((pp 1))
			    (do ((p point (+ p 1)))
				((= p end))
			      (format ostr "~2,'0x " (read-byte bin-str))
			      (incf pp))
			    (do nil
				((>= pp 3) (values nil end))
			      (princ "   " ostr)
			      (incf pp))))
			 (t
			  (format ostr "~2,'0x " x)
			  (values (cons #xCB (cons x (rbad bin-str (- len 1) 2 ostr)))
				  point+len)))))
		(t
		 (cond ((= x #xCB)
			(read-bins-and-display bin-str (+ point 1) end bank ostr CBxx))
		       (t
			(let* ((len (mn-len (svref *optable* x)))
			       (point+len (+ point len)))
			  (cond ((> point+len end) ;現在地+命令長がendを越える場合
				 (let ((pp 1))
				   (do ((p point (+ p 1)))
				       ((= p end))
				     (format ostr "~2,'0x " (read-byte bin-str))
				     (incf pp))
				   (do nil
				       ((>= pp 4) (values nil end))
				     (princ "   " ostr)
				     (incf pp))))
				(t
				 (values (cons x (rbad bin-str (- len 1) 3 ostr))
					 point+len))))))))))))

(defun rbad (bin-str len allrange ostr)
  (if (= len 0)
      (if (<= allrange 0)
	  nil
	  (progn
	    (format ostr "   ")
	    (rbad bin-str len (- allrange 1) ostr)))
      (let ((x (read-byte bin-str)))
	(format ostr "~2,'0x " x)
	(cons x (rbad bin-str (- len 1) (- allrange 1) ostr)))))
	
	   

;バンク:行 数列 オペコード　オペランド~%
;という1行の出力をする
;streamの現在地点を返す
;ただし、ファイルの終端に達した場合はnilを返す
(defun print-line (bin-str point end bank ostr)
  (let* ((b (multiple-value-bind
		  (x y)
		(read-bins-and-display bin-str point end bank ostr)
	      (list x y)))
	 (bins (car b))
	 (pos (cadr b)))
    (if (null bins)
	(if (= pos end)
	    (progn (format ostr "[unknown]~%") pos)
	    nil)
	(progn
	  (cond ((= (car bins) #xCB)
		 (print-mnemonic (svref *optable-cb* (cadr bins)) (cdr bins) point ostr))
		(t
		 (print-mnemonic (svref *optable* (car bins)) bins point ostr)))
	  (terpri ostr)
	  pos))))



;startからendまでの逆アセ
;普通はt、EOFに達するとnilを返す
(defun disassemble-z80 (bin-str start end bank ostr)
  (if (= start end)
      t
      (do ((pos start (print-line bin-str pos end bank ostr)))
	  ((or (null pos)
	       (= pos end))
	   (progn (terpri ostr)
		  (if (null pos) nil t))))))





;バンク0の処理
(defun header (bin-str ostr)
  (format ostr "\"リスタート\"~%")
  (disassemble-z80 bin-str #x0000 #x0040 0 ostr)
  (format ostr "\"V-ブランク割り込みコール\"~%")
  (disassemble-z80 bin-str #x0040 #x0048 0 ostr)
  (format ostr "\"LCDコントローラ割り込みコール\"~%")
  (disassemble-z80 bin-str #x0048 #x0050 0 ostr)
  (format ostr "\"タイマ割り込みコール\"~%")
  (disassemble-z80 bin-str #x0050 #x0058 0 ostr)
  (format ostr "\"シリアル通信割り込みコール\"~%")
  (disassemble-z80 bin-str #x0058 #x0060 0 ostr)
  (format ostr "\"キー入力割り込みコール\"~%")
  (disassemble-z80 bin-str #x0060 #x0068 0 ostr)
  (format ostr "\"プログラム開始\"~%")
  (empty-read bin-str #x0068 #x0100)
  (disassemble-z80 bin-str #x0100 #x0104 0 ostr)
  (format ostr "\"任天堂ロゴ\"~%")
  (read-data bin-str #x0104 #x0134 0 ostr)
  (format ostr "\"タイトル\"~%")
  (read-data bin-str #x0134 #x0143 0 ostr)
  (format ostr "\"カラー対応判定\"~%")
  (let ((x (read-byte bin-str)))
    (prinhex x 2 ostr)
    (cond ((zerop x) (format ostr ":カラー非対応~%~%"))
	  ((= x #x80) (format ostr ":カラー対応~%~%"))
	  (t (format ostr ":未知~%~%"))))
  ;ライセンスコード:未実装
  (read-byte bin-str) (read-byte bin-str)
  (format ostr "\"GB/SGB判定\"~%")
  (let ((x (read-byte bin-str)))
    (prinhex x 2 ostr)
    (cond ((zerop x) (format ostr ":ゲームボーイ~%~%"))
	  ((= x #x03) (format ostr ":スーパーゲームボーイ~%~%"))
	  (t (format ostr ":未知~%~%"))))
  ;カートリッジ型:未実装
  (format ostr "\"カートリッジ型\"~%")
  (read-byte bin-str)
  ;ROMサイズ:未実装
  (format ostr "\"ROMサイズ\"~%")
  (read-byte bin-str)
  ;RAMサイズ:未実装
  (format ostr "\"RAMサイズ\"~%")
  (read-byte bin-str)
  (format ostr "\"リージョン\"~%")
  (let ((x (read-byte bin-str)))
    (prinhex x 2 ostr)
    (cond ((zerop x) (format ostr ":日本~%~%"))
	  ((= x #x01) (format ostr ":日本以外~%~%"))
	  (t (format ostr ":未知~%"))))
  (format ostr "\"ライセンスコード\"~%")
  (let ((x (read-byte bin-str)))
    (prinhex x 2 ostr)
    (cond ((= x #x79) (format ostr ":ACCOLADE~%~%"))
	  ((= x #xA4) (format ostr ":KONAMI~%~%"))
	  ((= x #x33) (format ostr ":0144h/0145hをライセンスコードとする~%~%"))
	  (t (format ostr ":未知~%~%"))))
  (format ostr "\"ROMのバージョン\"~%~d~%~%" (read-byte bin-str))
  ;ヘッダチェック:未実装
  (read-byte bin-str)
  ;グローバルチェック:未実装
  (read-byte bin-str)(read-byte bin-str)
  (terpri ostr))



(defparameter description-lst nil)

(defun disassemble-file (bin-path &optional (out-path nil) (cfg-path nil))
  (with-open-file (bin-str (parse-native-namestring bin-path)
		       :direction :input
		       :element-type 'unsigned-byte)
    (let ((ostr (if (null out-path)
		    t
		    (open (parse-native-namestring out-path)
			  :direction :output
			  :if-exists :supersede))))
      (format t "[ROM0]~%")
      (if out-path (format ostr "[ROM0]~%"))
      (header bin-str ostr)
      (format ostr "[ユーザー領域]~%")
      (if (null cfg-path)
	  (progn
	    (disassemble-z80 bin-str #x0150 #x4000 0 ostr) ;バンク0の逆アセ
	    (do ((b 1 (+ b 1)))
		((progn
		   (format t "[ROM~d]~%" b)
		   (if out-path (format ostr "[ROM~d]~%" b))
		   (not (disassemble-z80 bin-str #x4000 #x8000 b ostr))))))
	  (with-open-file (cstr (parse-native-namestring cfg-path)
				:direction :input)
	    (setf description-lst (read cstr nil))
	    (do ((begin #x0150)
		 (next-data (read cstr nil) (read cstr nil)))
		((null next-data) (disassemble-z80 bin-str begin #x4000 0 ostr))
	      (disassemble-z80 bin-str begin next-data 0 ostr) ;このソースを書いて数年後に掘り起こしたらなぜかここが4変数しかなくてコンパイルエラーが出た。よく読まずに0を挿入したらいちおう動いた。
	      (setf begin (read cstr nil))
	      (read-data bin-str next-data begin 0 ostr :caption (read cstr nil)))
	    (do ((b 1 (+ b 1)))
		((progn
		   (format t "[ROM~x]~%" b)
		   (if out-path (format ostr "[ROM~x]~%" b))
		   (not (do ((begin #x4000)
			     (next-data (read cstr nil) (read cstr nil)))
			    ((null next-data) (disassemble-z80 bin-str begin #x8000 b ostr))
			  (disassemble-z80 bin-str begin next-data b ostr)
			  (setf begin (read cstr nil))
			  (read-data bin-str next-data begin b ostr :caption (read cstr nil)))))))))
      (when out-path (close ostr)))))

    
    

;入力した数値からバンク:point を返す
(defun convert-to-bank (num)
  (let* ((m (mod num #x4000))
	 (d (/ (- num m) #x4000)))
    (format t "~2,'0x:~4,'0x" d (if (zerop d) m (+ m #x4000)))))

;(disassemble-file "testrom.gb" "assembly.txt" "testrom_cfg.txt")

;; (defmacro b (_xyzz)
;;  `(format t "~b" ,_xyzz))

;; (defmacro d (_xyzzz)
;;  `(format t "~d" ,_xyzzz))

;; (defmacro x (_xyzz)
;;   `(format t "~x" ,_xyzzzz))
