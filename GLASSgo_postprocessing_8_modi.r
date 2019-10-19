# GLASSgo postprocessing script

# dependencies: 
## CDhit
require(seqinr)
require(RSQLite)
require(rentrez)
require(phangorn)
require(stringi)
# parameters from function call:

#CALL:
#R --slave -f  /home/jens/jensSicherung/GLASSgo2/GLASSgo_postprocessing_2.r --args filename=sRNA.txt duplicates_allowed=TRUE synteny_window=3000 refpath=/media/cyano_share/data/GLASSgo_postprocessing/accession_to_refseq cop_path=/media/cyano_share/data/GLASSgo_postprocessing/CopraRNA_available_organisms.txt featpath=/media/cyano_share/data/GLASSgo_postprocessing/GLASSgo_genome_tables_cop_only2.db name=testfile coprarna_compatible=TRUE
#R --slave -f  /home/jens/jensSicherung/GLASSgo2/GLASSgo_postprocessing_6.r --args filename="sRNA.txt" duplicates_allowed=FALSE synteny_window=3000  name=FnrS coprarna_compatible=TRUE ooi=NC_000913

## Apiwat'S modification
#un-remove fasta file of gene synteny

duplicates_allowed<-F  # if FALSE only one homolog from one organism is plotted
name<-"sRNA"  # name of the investigated sRNA
filename<-"sRNA.txt" # result fasta file from GLASSgo
refpath<-"/media/cyano_share/data/GLASSgo_postprocessing/accession_to_refseq" # look-up table for refseq assignment updated with "update_accession_to_refseq.r"
cop_path<- "/media/cyano_share/data/GLASSgo_postprocessing/CopraRNA_available_organisms.txt" # same file as for CopraRNA


featpath<-"/media/cyano_share/data/GLASSgo_postprocessing/GLASSgo_genome_tables_cop_only3.db" # path to the gene-neighborhood SQLite database file, auto-updated for missing genomes
synteny_window<-3000 # number of bases upstream and downstream of the sRNA that were searched for protein coding genes for the synteny analysis
ooi<-"NC_000913" # organism of interest - important for the CopraRNA organism selection
dbname_16S<-"/media/cyano_share/data/GLASSgo_postprocessing/rRNA.db" # path to the SQLite database storing SILVA 16S rDNA sequences
coprarna_compatible<-T # organsims are filtered based on the CopraRNA_available_organisms.txt file

maxorgs<-20 # number of orgs for CopraRNA prediction
mindis<-0.001 # organisms which have a lower cophonetic distances to each other in a 16S phylogentic tree are excluded to reduce complexity. A respective reference organism is kept
maxdis<-0.09 # # organisms which have a higher cophonetic distances to each the ooi are excluded.
closeorgs<-3 # number of closest relatives to the ooi for CopraRNA
clustervalue<-1.5 # the higher the higher the resolution of tree sub-groups
wildcard<-c("NZ_CP007542.1")
refseq_required=TRUE
outorg="internal" # genome accssion of outgroup organsim for phylogenetic tree, if "internal" organism with highest distance to ooi is selected as outgroup
min_size<-4  # minimal size of tree-based cluster
mixed_sources=T # True if several GLAssgo outputs are pasted together
reduced_svg=T


args <- commandArgs(trailingOnly = TRUE) 

for(i in 1:length(args)){
	temp<-strsplit(args[i],"=")
	temp<-temp[[1]]
	temp1<-temp[1]
	temp2<-temp[2]
	assign(as.character(temp1),temp2)
 }
 
 print(name)
 
if(file.exists(featpath)==F){
	con <- dbConnect(RSQLite::SQLite(), featpath)
	dbDisconnect(con)
}

duplicates_allowed<-as.logical(duplicates_allowed)
synteny_window<-as.numeric(synteny_window)

# Extracts the information from the fasta header and writes it into a tabular format
export_ncRNA_coordinates<-function(x){ 
  header_row <- grep(">", x)
  headers <- as.character(x[header_row])
  seqs<-as.character(x[header_row+1])
  
  # slice and clean strain_name from header
  strain_names <- headers
  strain_names <- gsub(".*[0-9]{1,}-[0-9]{1,} ","", strain_names)
  strain_names <- gsub(",.*","", strain_names)
  strain_names <- gsub("genome assembly","", strain_names)
  strain_names <- gsub("complete genome","", strain_names)
  strain_names <- gsub("\\sgenome-p.c.VAL.*","", strain_names)
  strain_names <- gsub("\\ssequence-p.c.VAL.*","", strain_names)
  strain_names <- gsub("\\s-p.c.VAL.*","", strain_names)
  strain_names <- gsub("\\sDNA.*","", strain_names)
  #strain_names
  
  # get locations contain start, end and strand infromation
  locations <- c()
  accessions <- c()

  for (i in 1:length(headers)){
    loc <- strsplit(headers, " ")[[i]][1] # strip genome information
    acc <- strsplit(loc, ":")[[1]][1] # get accession
    #acc <- strsplit(loc, "\\.")[[1]][1] # remove .1 suffix of accession
    loc <- strsplit(loc, ":")[[1]][2] # get location
    #cat(acc, loc, "\n")
    locations <- c(locations, loc)
    accessions <- c(accessions, gsub(">", "", acc))
  }
  #locations
  #accessions
  
  # summarize strand, start, end, name, header and sequence information
  out<-matrix(, length(locations), 7)
  colnames(out)<-c("Accesion_number", "Strand","start","end","name","Full_header","sequence")
  out[, 1] <- accessions
  out[, 2]<-"+"
  for(i in 1:length(locations)){
    temp<-grep("c",locations[i])
	
	
    if(length(temp)==1){
      out[i, 2]<-"-"
    }
    temp<-gsub("c","",locations[i])
    temp<-strsplit(temp,"-")
    out[i, 3] <- temp[[1]][1]
    out[i, 4] <- temp[[1]][2]
  }
  out[, 5] <- strain_names
  out[, 6] <- as.character(headers)
  out[, 7] <- as.character(seqs)
  out
}


# assigns refseq IDs based on the Accesion number using a look-up table 
to_refseq2<-function(result, refpath="../accession_to_refseq"){
		load(refpath)
		result<-gsub("\\..*","",result)
		temp<-c()
		
		for(i in 1:length(result)){
		temp1<-grep(result[i],ref[,"full_genome_entry"])
		temp<-c(temp,temp1[1])
		}
		temp<-ref[temp,"Chromosomes.RefSeq"]
		refseq<-temp
		refseq
	}

rand_extension<-function(x){
	ra<-stri_rand_strings(1,length=4,  pattern = "[A-Za-z0-9]")
	temp<-paste(gsub("\"","",x),ra,sep="_")
	#temp<-gsub("\"","",temp)
	
	temp
}
	
# load gene neighborhood data form SQLite database if not present call function to add the genome to the database
data_preparation_sqlite<-function(coor,featpath="/media/ramdisk_brainstorm/jens/genome_tables2.db", windo=3000){ 
 out<-list()
 con <- dbConnect(SQLite(), dbname=featpath, ":memory:")
 #dbBegin(con)
 man<-c()
 mas<-c()
 for(i in 1:nrow(coor)){
	print(i)
    temp<-coor[i,]
    stra<--1
    if(temp[2]=="+"){
      stra<-1
    }
    na<-as.character(temp[5])
    nam<-paste(temp[1],temp[3], sep="_")
    s<-as.numeric(temp[3])
    e<-as.numeric(temp[4])
	tempn<-temp
	if(dbExistsTable(con, paste0(coor[i,1]))==F){
		tryCatch(generate_feattable_fetch(coor[i,1], featpath=featpath, connection=con), error=function(e) {print("NCBI database download failed")})
		#dbDisconnect(con)
		#con <- dbConnect(SQLite(), dbname=featpath, ":memory:")
	}
	if(dbExistsTable(con, paste0(coor[i,1]))==T){
		temp<-paste("SELECT * FROM ","'",coor[i,1],"'"," WHERE rowid = 1 ",sep="")
		temp<-dbGetQuery(con,temp)
	if(temp[1,1]!="no_info"){
		temp4<-data.frame(strand=numeric(),start=numeric(),end=numeric(), gene_name=character(), locus_tag=character(), AA_sequence=character())
		temp<-paste("SELECT strand,start,end,gene_name,locus_tag FROM ","'",coor[i,1],"'"," WHERE start >= ", max(0,(s-windo))," AND end <= ",(e+windo) ,sep="")
		tempa<-paste("SELECT AA_sequence FROM","'",coor[i,1],"'"," WHERE start >= ", max(0,(s-windo))," AND end <= ",(e+windo) ,sep="")
		temp<-dbGetQuery(con,temp)
		if(nrow(temp)>0){
			tempa<-dbGetQuery(con,tempa)
			tempa<-as.character(unlist(lapply(tempa[[1]], memDecompress, asChar=T, type="gzip")))
			temp<-cbind(temp,tempa)
			temp4<-rbind(temp4,temp)
		}
		
		temp2<-paste("SELECT strand,start,end,gene_name,locus_tag FROM ","'",coor[i,1],"'"," WHERE start <= ", max(0,(s-windo))," AND end >= ",(e-windo) ,sep="")
		tempb<-paste("SELECT AA_sequence FROM ","'",coor[i,1],"'"," WHERE start <= ", max(0,(s-windo))," AND end >= ",(e-windo) ,sep="")
		temp2<-dbGetQuery(con,temp2)
		if(nrow(temp2)>0){
			tempb<-dbGetQuery(con,tempb)
			tempa<-as.character(unlist(lapply(tempb[[1]], memDecompress, asChar=T, type="gzip")))
			temp2<-cbind(temp2,tempa)
			temp4<-rbind(temp4,temp2)
			}
		
		temp3<-paste("SELECT strand,start,end,gene_name,locus_tag FROM ","'",coor[i,1],"'"," WHERE start <= ", max(0,(s+windo))," AND end >= ",(e+windo) ,sep="")
		tempc<-paste("SELECT AA_sequence FROM ","'",coor[i,1],"'"," WHERE start <= ", max(0,(s+windo))," AND end >= ",(e+windo) ,sep="")
		temp3<-dbGetQuery(con,temp3)
		if(nrow(temp3)>0){
			tempc<-dbGetQuery(con,tempc)
			tempa<-as.character(unlist(lapply(tempc[[1]], memDecompress, asChar=T, type="gzip")))
			temp3<-cbind(temp3,tempa)
			temp4<-rbind(temp4,temp3)
		}
		if(nrow(temp4)>0){
		temp_out<-temp4
		#temp_out<-rbind(temp, temp2, temp3)
		colnames(temp_out)[6]<-"AA_sequence"
		temp_out[which(temp_out[,1]==1),1]<-"+"
		temp_out[which(temp_out[,1]==0),1]<-"-"
		dup<-which(duplicated(temp_out[,c(2,5)]))
	if(length(dup)>0){
		temp_out<-temp_out[-dup,]
	}
    if(length(dim(temp_out))<2 ){
		temp_out<-t(as.matrix(temp_out))
    }
    if(nrow(temp_out)>0){
		ma<-max(as.numeric(temp_out[,3]))
		mi<-min(as.numeric(temp_out[,2]))
		aa<-as.numeric(temp_out[,2])-mi
		bb<-as.numeric(temp_out[,3])-mi
		s_srna<-min(as.numeric(tempn[3:4]))-mi
		e_srna<-max(as.numeric(tempn[3:4]))-mi
		temp_out<-cbind(temp_out,aa,bb,rep(s_srna,nrow(temp_out)),rep(e_srna,nrow(temp_out)),rep(stra,nrow(temp_out)),rep(na,nrow(temp_out)))
		orf<-grep("orf_", temp_out[,"locus_tag"])
		if(length(orf)>0){
			temp_out[orf,"locus_tag"]<-paste(tempn[1],temp_out[orf,"locus_tag"], sep="_")
		}
		nan<-which(is.na(temp_out[,"locus_tag"]))
		if(length(nan)>0){
		
			no<-match(coor[i,1], coor[,1])
			no<-setdiff(no, i)
			nam3<-paste(coor[i,1],no,1:length(nan),sep="_")
			temp_out[nan,"locus_tag"]<-nam3
		}
		
	temp_out[,"locus_tag"]<-unlist(lapply(temp_out[,"locus_tag"],rand_extension))
	d<-ma-mi
	man<-c(man,d)
	mas<-c(mas,s_srna)
	out[[length(out)+1]]<-temp_out
	names(out)[length(out)]<-nam
	}
     }
    }
	}
  }	
#dbCommit(con)
dbDisconnect(con)
d<-max(d)
mas<-max(mas)	
s_vect<-c()
exist<-na.omit(match(names(out), paste(coor[,1],coor[,3], sep="_")))
outt<-list(out, 1,  d, coor[exist,], s_vect)	
outt	
}

# fetches missing Refseq .gbk files from the NCBI server

generate_feattable_fetch<-function(idvect,featpath=FALSE, connection=con){
	for(i in 1:length(idvect)){
		gen <- entrez_fetch(db="nucleotide", id=idvect[i],rettype="gb",retmode="text")
		write.table(gen, file=as.character(idvect[i]), sep="\t", quote=FALSE, row.names=F, col.names=F)
		generate_feattable(idvect[i], featpath=featpath, connection=connection)
		unlink(idvect[i])
	}
}



# modifies Refseq .gbk files to a tabular format and adds it to the SQLite database
generate_feattable<-function(idvector, genomepath=FALSE, featpath=FALSE, connection=connection){
	con<-connection
	#wd<-getwd()
	pa<-function(x){
				x<-paste("x'", x, "'", sep="")
				x
	}
	# if(featpath==FALSE){
		# dir.create("feattables")
	# }

	# if(genomepath!=FALSE){
		# setwd(genomepath)
	# }
	ids<-idvector
	if(length(ids)>0){
		for(i in 1:length(ids)){
			temp_full<-read.delim(as.character(ids)[i])[,1]
			temp_full<-gsub("\\\n *","",temp_full)
			anfang<-grep("FEATURES   ",temp_full)
			ende<-grep("ORIGIN   ",temp_full)
			if(length(ende)==0){
				ende<-length(temp_full)
			}
			name<-grep("VERSION  ",temp_full)
			for(jj in 1:length(anfang)){
			temp<-temp_full[anfang[jj]:ende[jj]]
			tax<-grep("taxon:", temp)
			tax<-gsub(".*taxon:","",temp[tax])
			name1<-temp_full[name[jj]]
			name1<-gsub("VERSION *","",name1)
			name1<-strsplit(name1," ")
			name1<-name1[[1]][1]
			temp_gene<-grep("gene   ",temp)
			temp_cds<-grep("CDS   ",temp)
			
			#
				if(length(temp_gene)>length(temp_cds)){
					accession_info<-matrix(,length(temp_gene),6)
					colnames(accession_info)<-c("strand","start","end","gene_name","locus_tag","AA_sequence")
					accession_info[,1]<-1 # 1 equals plus strand
					for(j in 1:length(temp_gene)){
						if(j<length(temp_gene)){
							temp_y<-temp[temp_gene[j]:(temp_gene[j+1]-1)]
						}
						if(j==length(temp_gene)){
							temp_y<-temp[temp_gene[j]:(length(temp)-1)]
						}
						comp<-grep("complement",temp_y[1])
						if(length(comp)==0){
						coor<-gsub(" ","",temp_y[1])
						coor<-gsub("gene","",coor)
						coor1<-coor
						coor<-strsplit(coor,"\\.\\.")
						s<-as.numeric(coor[[1]][1])
						e<-as.numeric(coor[[1]][2])
						if(is.na(s)==FALSE & is.na(e)==FALSE){
							accession_info[j,2]<-coor[[1]][1]
							accession_info[j,3]<-coor[[1]][2]
						}
						}
						if(length(comp)==1){
						coor1<-gsub("gene","",temp_y[1])
						coor1<-gsub(" ","",coor1)
						coor<-gsub("gene.*complement\\(","",temp_y[1])
						coor<-gsub("\\)","",coor)
						coor<-gsub(" ","",coor)
						coor<-strsplit(coor,"\\.\\.")
						s<-as.numeric(coor[[1]][1])
						e<-as.numeric(coor[[1]][2])
						if(is.na(s)==FALSE & is.na(e)==FALSE){
							accession_info[j,2]<-coor[[1]][1]
							accession_info[j,3]<-coor[[1]][2]
							accession_info[j,1]<-0 # 1 equals minus strand
						}
						}
						tempg<-grep("/gene=",temp_y)
						if(length(tempg)>0){
							tempg<-gsub("/gene=","",temp_y[tempg[1]])
							tempg<-gsub(" ","",tempg)
							accession_info[j,4]<-tempg
						}
						templ<-grep("/locus_tag=",temp_y)
						if(length(temp)>0){
							templ<-gsub("/locus_tag=","",temp_y[templ[1]])
							templ<-gsub(" ","",templ)
							accession_info[j,5]<-templ
						}
						cds<-grep("CDS", temp_y)
						if(length(cds)==1){
							coor2<-gsub("CDS","",temp_y[cds])
							coor2<-gsub(" ","",coor2)
							if(coor2==coor1){
								# tempp<-grep("/product=", temp_y)
								# if(length(tempp)==1){
									# tempp<-gsub(" */product=","",temp_y[tempp])
									# accession_info[j,6]<-tempp
								# }
								tempp<-grep("/translation=", temp_y)
								if(length(tempp)==1){
									tempp<-gsub(" */translation=","",temp_y[tempp])
									accession_info[j,6]<-tempp
								}
							}
						}
					}
			feat<-accession_info
			no_tag<-which(is.na(feat[,"locus_tag"]))
			if(length(no_tag)>0){
				feat[no_tag,"locus_tag"]<-paste("locus_",1:length(no_tag),sep="")
			}
			if(length(tax)==0){
					tax<-"no_tax_info"
			}
			 feat<-list(feat,tax)
			# if(featpath!=FALSE){
				# di<-featpath
			# }
			# if(featpath==FALSE){
				# di<-featpath
			# }
			nas1<-which(is.na(feat[[1]][,4]))
			feat[[1]][nas1,4]<-paste("orf_",seq(1,length(nas1)),sep="")

		}
		
		# 
			if(length(temp_gene)<length(temp_cds)){
					temp_gene<-temp_cds
					if(length(temp_gene)>0){
					accession_info<-matrix(,length(temp_gene),6)
					colnames(accession_info)<-c("strand","start","end","gene_name","locus_tag","AA_sequence")
					accession_info[,1]<-1 # 1 equals plus strand
					for(j in 1:length(temp_gene)){
						if(j<length(temp_gene)){
							temp_y<-temp[temp_gene[j]:(temp_gene[j+1]-1)]
						}
						if(j==length(temp_gene)){
							temp_y<-temp[temp_gene[j]:(length(temp)-1)]
						}
						comp<-grep("complement",temp_y[1])
						if(length(comp)==0){

						coor<-gsub(" ","",temp_y[1])
						coor<-gsub("CDS","",coor)
						coor1<-coor
						coor<-strsplit(coor,"\\.\\.")
						s<-as.numeric(coor[[1]][1])
						e<-as.numeric(coor[[1]][2])
						if(is.na(s)==FALSE & is.na(e)==FALSE){
							accession_info[j,2]<-coor[[1]][1]
							accession_info[j,3]<-coor[[1]][2]
						}
						}
						if(length(comp)==1){
						coor1<-gsub("CDS","",temp_y[1])
						coor1<-gsub(" ","",coor1)
						coor<-gsub("CDS.*complement\\(","",temp_y[1])
						coor<-gsub("\\)","",coor)
						coor<-gsub(" ","",coor)

						coor<-strsplit(coor,"\\.\\.")
						s<-as.numeric(coor[[1]][1])
						e<-as.numeric(coor[[1]][2])
						if(is.na(s)==FALSE & is.na(e)==FALSE){
							accession_info[j,2]<-coor[[1]][1]
							accession_info[j,3]<-coor[[1]][2]
							accession_info[j,1]<-0 # 0 equals minus strand
						}
						}
						tempg<-grep("/gene=",temp_y)
						if(length(tempg)>0){
							tempg<-gsub("/gene=","",temp_y[tempg[1]])
							tempg<-gsub(" ","",tempg)
							accession_info[j,4]<-tempg
						}
						templ<-grep("/locus_tag=",temp_y)
						if(length(temp)>0){
							templ<-gsub("/locus_tag=","",temp_y[templ[1]])
							templ<-gsub(" ","",templ)
							accession_info[j,5]<-templ
						}
						cds<-grep("CDS", temp_y)

								# tempp<-grep("/product=", temp_y)
								# if(length(tempp)==1){
									# tempp<-gsub(" */product=","",temp_y[tempp])
									# accession_info[j,6]<-tempp
								# }
								tempp<-grep("/translation=", temp_y)
								if(length(tempp)==1){
									tempp<-gsub(" */translation=","",temp_y[tempp])
									accession_info[j,6]<-tempp
								}
					}
			feat<-accession_info
			no_tag<-which(is.na(feat[,"locus_tag"]))
			if(length(no_tag)>0){
				feat[no_tag,"locus_tag"]<-paste("locus_",1:length(no_tag),sep="")
			}
			if(length(tax)==0){
					tax<-"no_tax_info"
			}
			feat<-list(feat,tax)
			# if(featpath!=FALSE){
				# di<-featpath
				# print(di)
			# }
			# if(featpath==FALSE){
				# di<-featpath
				# print(di)
			# }
			nas1<-which(is.na(feat[[1]][,4]))
			feat[[1]][nas1,4]<-paste("orf_",seq(1,length(nas1)),sep="")
			
			
			
			}
		}
	
		#
		if(length(temp_gene)==0){
				if(length(tax)==0){
					tax<-"no_tax_info"
				}
				feat<-"no_info"
				feat<-list(feat,tax)

			# if(featpath!=FALSE){
				# di<-featpath
				# print(di)
			# }
			# if(featpath==FALSE){
				# di<-featpath
				# print(di)
			# }
			
			
			
		}
		
		# write to database
		#con <- dbConnect(SQLite(), dbname=di)
		
		temp<-feat[[1]]
		temp<-as.data.frame(temp)
		if(temp[1,1]!="no_info"){
			temp[,1]<-as.integer(as.character(temp[,1]))
			temp[,2]<-as.integer(as.character(temp[,2]))
			temp[,3]<-as.integer(as.character(temp[,3]))
			temp[,6]<-(as.character(temp[,6]))
			# temp[,4]<-(as.character(temp[,4]))
			# temp[,5]<-(as.character(temp[,5]))
			temp_AA<-lapply(temp[,6], memCompress, type="gzip")
			# temp_loc<-lapply(temp[,5], memCompress, type="gzip")
			# temp_gene<-lapply(temp[,4], memCompress, type="gzip")
			#temp_AA<-lapply(temp_AA, paste, collapse="")
			#temp_AA<-unlist(lapply(temp_AA, pa))
			#temp[,6]<-as.character(temp_AA)
			temp<-temp[,1:5]
			temp3<-data.frame(temp, AA_sequence=I(temp_AA))
			# temp[,6]<-I(unlist(lapply(temp_AA, pa)))
			#temp[,6]<-I(lapply(temp_AA, memCompress, type="gzip"))
			# 
			#con <- dbConnect(SQLite(), dbname="test28.db", ":memory:")
			#dbBegin(con)
			#dbWriteTable(con, name1, overwrite=T, temp)
			 dbGetQuery(con, paste("CREATE TABLE '", name1 ,"' (strand INTEGER, start INTEGER, end INTEGER, gene_name TEXT, locus_tag TEXT, AA_sequence BLOB);",sep=""))
			 dbGetQuery(con, paste("INSERT INTO '", name1,"' (strand, start, end, gene_name, locus_tag, AA_sequence) VALUES (:strand, :start, :end, :gene_name, :locus_tag, :AA_sequence)",sep=""), params=temp3)
			# dbCommit(con)
			# memDecompress(dbGetQuery(con, "SELECT AA_sequence from 'CP008862.2'  WHERE start <= 1000;")[[1]][[1]], type="gzip", asChar=T)
			# dbDisconnect(con)
			# for(jj in 1:length(temp_AA)){
				# query <- paste("INSERT INTO '", name1,"' (strand, start, end, gene_name, locus_tag, AA_sequence) VALUES (", paste(temp[jj,1],temp[jj,2],temp[jj,3],paste("'",temp[jj,4],"'",sep="") ,paste("'",temp[jj,5],"'",sep=""),temp_AA[jj], sep=","), ");", sep="")
				# dbGetQuery(con, query) 
			# }
			# dbCommit(con)
			# #ca<-paste("UPDATE '", name1,"' SET AA_sequence =:temp_AA WHERE 'locus_tag' =:id;",sep="")
			#dbExecute(con, ca, params=data.frame(temp_AA=temp_AA, id=temp[,5]))
			}
		if(temp[1,1]=="no_info"){
			dbWriteTable(con, name1, overwrite=T, temp)
		}
		
		#dbDisconnect(con)
	
	}
	}

	}
	# setwd(wd)
}

generate_feattable_old<-function(idvector, genomepath=FALSE, featpath=FALSE){
	wd<-getwd()
	setwd
	if(featpath==FALSE){
		dir.create("feattables")
	}

	if(genomepath!=FALSE){
		setwd(genomepath)
	}
	ids<-idvector
	if(length(ids)>0){
		for(i in 1:length(ids)){				
			temp_full<-read.delim(as.character(ids)[i])[,1]
			temp_full<-gsub("\\\n *","",temp_full)
			anfang<-grep("FEATURES   ",temp_full)
			ende<-grep("ORIGIN   ",temp_full)
			if(length(ende)==0){
				ende<-length(temp_full)
			}
			name<-grep("VERSION  ",temp_full)
			for(jj in 1:length(anfang)){
			temp<-temp_full[anfang[jj]:ende[jj]]
			tax<-grep("taxon:", temp)
			tax<-gsub(".*taxon:","",temp[tax])
			name1<-temp_full[name[jj]]
			name1<-gsub("VERSION *","",name1)
			name1<-strsplit(name1," ")
			name1<-name1[[1]][1]
			temp_gene<-grep("gene   ",temp)
			temp_cds<-grep("CDS   ",temp)
			if(length(temp_gene)>0){
				accession_info<-matrix(,length(temp_gene),7)
				colnames(accession_info)<-c("strand","start","end","gene_name","locus_tag","product","AA_sequence")
				accession_info[,1]<-"+"
				for(j in 1:length(temp_gene)){
					if(j<length(temp_gene)){
						temp_y<-temp[temp_gene[j]:(temp_gene[j+1]-1)]
					}
					if(j==length(temp_gene)){
						temp_y<-temp[temp_gene[j]:(length(temp)-1)]
					}
					comp<-grep("complement",temp_y[1])
					if(length(comp)==0){
					coor<-gsub(" ","",temp_y[1])
					coor<-gsub("gene","",coor)
					coor1<-coor
					coor<-strsplit(coor,"\\.\\.")
					s<-as.numeric(coor[[1]][1])
					e<-as.numeric(coor[[1]][2])
					if(is.na(s)==FALSE & is.na(e)==FALSE){
						accession_info[j,2]<-coor[[1]][1]
						accession_info[j,3]<-coor[[1]][2]
					}
					}
					if(length(comp)==1){
					coor1<-gsub("gene","",temp_y[1])
					coor1<-gsub(" ","",coor1)
					coor<-gsub("gene.*complement\\(","",temp_y[1])
					coor<-gsub("\\)","",coor)
					coor<-gsub(" ","",coor)
					coor<-strsplit(coor,"\\.\\.")
					s<-as.numeric(coor[[1]][1])
					e<-as.numeric(coor[[1]][2])
					if(is.na(s)==FALSE & is.na(e)==FALSE){
						accession_info[j,2]<-coor[[1]][1]
						accession_info[j,3]<-coor[[1]][2]
						accession_info[j,1]<-"-"
					}
					}
					tempg<-grep("/gene=",temp_y)
					if(length(tempg)>0){
						tempg<-gsub("/gene=","",temp_y[tempg[1]])
						tempg<-gsub(" ","",tempg)
						accession_info[j,4]<-tempg
					}
					templ<-grep("/locus_tag=",temp_y)
					if(length(temp)>0){
						templ<-gsub("/locus_tag=","",temp_y[templ[1]])
						templ<-gsub(" ","",templ)
						accession_info[j,5]<-templ
					}
					cds<-grep("CDS", temp_y)
					if(length(cds)==1){
						coor2<-gsub("CDS","",temp_y[cds])
						coor2<-gsub(" ","",coor2)
						if(coor2==coor1){
							tempp<-grep("/product=", temp_y)
							if(length(tempp)==1){
								tempp<-gsub(" */product=","",temp_y[tempp])
								accession_info[j,6]<-tempp
							}
							tempp<-grep("/translation=", temp_y)
							if(length(tempp)==1){
								tempp<-gsub(" */translation=","",temp_y[tempp])
								accession_info[j,7]<-tempp
							}
						}
					}
				}
		feat<-accession_info
		if(length(tax)==0){
				tax<-"no_tax_info"
		}
		feat<-list(feat,tax)
        if(featpath!=FALSE){
			di<-featpath
		}
        if(featpath==FALSE){
			di<-featpath
		}
		nas1<-which(is.na(feat[[1]][,5]))
		feat[[1]][nas1,5]<-paste("orf_",seq(1,length(nas1)),sep="")
        con <- dbConnect(SQLite(), dbname=di, ":memory:")
		temp<-feat[[1]]
		temp<-as.data.frame(temp)
        if(temp[1,1]!="no_info"){
			print(i)
			temp[,2]<-as.numeric(as.character(temp[,2]))
			temp[,3]<-as.numeric(as.character(temp[,3]))
		}
		dbWriteTable(con, name1, overwrite=T, temp)
		dbDisconnect(con)
		}
		if(length(temp_gene)==0){
				temp_gene<-temp_cds
				if(length(temp_gene)>0){
				accession_info<-matrix(,length(temp_gene),7)
				colnames(accession_info)<-c("strand","start","end","gene_name","locus_tag","product","AA_sequence")
				accession_info[,1]<-"+"
				for(j in 1:length(temp_gene)){
					if(j<length(temp_gene)){
						temp_y<-temp[temp_gene[j]:(temp_gene[j+1]-1)]
					}
					if(j==length(temp_gene)){
						temp_y<-temp[temp_gene[j]:(length(temp)-1)]
					}
					comp<-grep("complement",temp_y[1])
					if(length(comp)==0){

					coor<-gsub(" ","",temp_y[1])
					coor<-gsub("CDS","",coor)
					coor1<-coor
					coor<-strsplit(coor,"\\.\\.")
					s<-as.numeric(coor[[1]][1])
					e<-as.numeric(coor[[1]][2])
					if(is.na(s)==FALSE & is.na(e)==FALSE){
						accession_info[j,2]<-coor[[1]][1]
						accession_info[j,3]<-coor[[1]][2]
					}
					}
					if(length(comp)==1){
					coor1<-gsub("CDS","",temp_y[1])
					coor1<-gsub(" ","",coor1)
					coor<-gsub("CDS.*complement\\(","",temp_y[1])
					coor<-gsub("\\)","",coor)
					coor<-gsub(" ","",coor)

					coor<-strsplit(coor,"\\.\\.")
					s<-as.numeric(coor[[1]][1])
					e<-as.numeric(coor[[1]][2])
					if(is.na(s)==FALSE & is.na(e)==FALSE){
						accession_info[j,2]<-coor[[1]][1]
						accession_info[j,3]<-coor[[1]][2]
						accession_info[j,1]<-"-"
					}
					}
					tempg<-grep("/gene=",temp_y)
					if(length(tempg)>0){
						tempg<-gsub("/gene=","",temp_y[tempg[1]])
						tempg<-gsub(" ","",tempg)
						accession_info[j,4]<-tempg
					}
					templ<-grep("/locus_tag=",temp_y)
					if(length(temp)>0){
						templ<-gsub("/locus_tag=","",temp_y[templ[1]])
						templ<-gsub(" ","",templ)
						accession_info[j,5]<-templ
					}
					cds<-grep("CDS", temp_y)

							tempp<-grep("/product=", temp_y)
							if(length(tempp)==1){
								tempp<-gsub(" */product=","",temp_y[tempp])
								accession_info[j,6]<-tempp
							}
							tempp<-grep("/translation=", temp_y)
							if(length(tempp)==1){
								tempp<-gsub(" */translation=","",temp_y[tempp])
								accession_info[j,7]<-tempp
							}
				}
		feat<-accession_info
		if(length(tax)==0){
				tax<-"no_tax_info"
		}
		feat<-list(feat,tax)
		if(featpath!=FALSE){
			di<-featpath
			print(di)
		}
        if(featpath==FALSE){
			di<-featpath
			print(di)
		}
		nas1<-which(is.na(feat[[1]][,5]))
		feat[[1]][nas1,5]<-paste("orf_",seq(1,length(nas1)),sep="")
         con <- dbConnect(SQLite(), dbname=di, ":memory:")
		temp<-feat[[1]]
		temp<-as.data.frame(temp)
        if(temp[1,1]!="no_info"){
		print(i)
		temp[,2]<-as.numeric(as.character(temp[,2]))
		temp[,3]<-as.numeric(as.character(temp[,3]))
	}
	dbWriteTable(con, name1, overwrite=T, temp)
	dbDisconnect(con)
		}
	}
		if(length(temp_gene)==0){
			if(length(tax)==0){
				tax<-"no_tax_info"
			}
			feat<-"no_info"
			feat<-list(feat,tax)

		if(featpath!=FALSE){
			di<-featpath
			print(di)
		}
        if(featpath==FALSE){
			di<-featpath
			print(di)
		}
		con <- dbConnect(SQLite(), dbname=di, ":memory:")
		temp<-feat[[1]]
		temp<-as.data.frame(temp)
        if(temp[1,1]!="no_info"){
		print(i)
		temp[,2]<-as.numeric(as.character(temp[,2]))
		temp[,3]<-as.numeric(as.character(temp[,3]))
	}
	dbWriteTable(con, name1, overwrite=T, temp)
	dbDisconnect(con)
		}
		}
		}

	}
	
}


divide<-function(number,candlist,p4,max_step=5,ooi){
	ooi_p<-grep(ooi, colnames(p4))
	#p5<-names(sort(p4[,ooi_p))
	more<-0
	stepsize<-floor(length(candlist)/number)
	stepsize<-min(max_step,stepsize)
	if(number>1){
		sel<-seq(1,length(candlist)*2,by=stepsize)
		sel<-sel[1:number]
		sel<-na.omit(sel)
		more<-number-length(sel)
		if(length(candlist)>1){
			cands<-names(sort(p4[candlist,ooi_p]))
		}
		if(length(candlist)==1){
			cands<-rownames(p4)[candlist]
		}
	}
	if(number==1){
		sel<-1
		#cands<-rownames(p4)[candlist]
		if(length(candlist)>1){
			cands<-names(sort(p4[candlist,ooi_p]))
		}
		if(length(candlist)==1){
			cands<-rownames(p4)[candlist]
		}
	}
	
	sel<-cands[sel]
	if(more>0){
		r<-setdiff(cands,sel)
		sel<-c(sel,r[1:more])
		}	
	#print(c(i,sel))
	sel	
}

locus_tag2org<-function(out2){
	tag<-c()
	org<-c()
	for(i in 1:length(out2[[1]])){
		temp_tag<-out2[[1]][[i]][,5]
		temp_org<-rep(names(out2[[1]])[i], length(temp_tag))
		tag<-c(tag,temp_tag)
		org<-c(org,temp_org)
	}
	out<-cbind(tag,org)
	out
}


# extract relevant amino acid sequences and write them to a fasta file
get_prot_fasta3<-function(out){
  fasta<-c()
  for(i in 1:length(out)){
    for(j in 1:nrow(out[[i]])){
        if(is.na(out[[i]][j,6])==F){
        temp<-as.character(out[[i]][j,6])
		na<-as.character(out[[i]][j,5])
		na<-gsub("\\\"","",na)
         na<-paste(">",na,sep="")
		 temp<-c(na,temp)
         fasta<-c(fasta,temp)
        }
      }
    }
  write.table(fasta, file="protein_fasta.txt", sep="\t", col.names=FALSE, row.names=FALSE, quote=FALSE)
}


# identify homologous proteins using CDhit
cdhit_run<-function(fasta="protein_fasta.txt", outname="psi", thres=0.3, psi=T){
  wd<-getwd()
  di<-paste(wd,"/", "psi_out",sep="")
  dir.create(di)
  if(psi==T){
    inp<-paste("./psi-cd-hit.pl -i ", fasta,  " -d 50 -o ", di,"/",outname, " -c ", thres, sep="")
  }
  if(psi==F){
    inp<-paste("cd-hit -i ", fasta,  " -d 50 -o ", di,"/",outname, " -c ",  thres ," -n 2", " -aL 0.6", sep="")
  }
  print(inp)
  system(inp)
  cd<-paste(di, "/", outname, ".clstr", sep="")
  cd<-read.delim(cd, header=F, sep="?")
  cd<-as.character(cd[,1])
  cd<-gsub("\t"," ", cd)
  cd
}

proc_cdhit<-function(x){ 
  clustlist<-list()
  numb<-grep(">Cluster", x)
  for(i in 1:length(numb)){
    if(i<length(numb)){
      end<-numb[i+1]-1
    }
    if(i==length(numb)){
      end<-length(x)
    }
    temp<-x[(numb[i]+1):end]
    temp<-gsub(".*aa, >","",temp)
    temp<-gsub("\\.\\.\\..*","",temp)
    clustlist[[i]]<-temp
  }
  clustlist	
}

# plot a pdf visualizing the synteny of predicted sRNA homologs


plot_function4<-function(out, cdhit_result, wind=3000, outformat="cairo_pdf", fasta="sRNA"){ 
  cdl<-unlist(lapply(cdhit_result,length))
  one<-which(cdl==1)
  more<-which(cdl>1)
  nl<-length(more)
  color = grDevices::colors()[grep('gr(a|e)y', grDevices::colors(), invert = T)]
  while(length(more)>length(color)){
	color<-c(color,color)
  }
  if(length(more)>0){
    collist<- sample(color, nl)
    for(i in 1:length(more)){
      names(cdhit_result)[more[i]]<-collist[i]
    }
  }
  names(cdhit_result)[one]<-"grey"
  numb<-ceiling(length(out)/5)
  
  
  
  le<-length(out)
  
   count<-4*le+1
	if(outformat=="pdf"){
	nam<-paste(fasta,"_synteny.pdf",sep="")
	pdf(nam,width=12, height=le*0.9,  useDingbats=F)
	#cairo_pdf(nam,width=11,  height = 1.1*le)
  }
  if(outformat=="png"){
	nam<-paste(fasta,"_synteny.png",sep="")
	png(nam,width=11,  height = 1.1*le,units="in", res=100)
  }
  if(outformat=="svg"){
	nam<-paste(fasta,"_synteny.svg",sep="")
	svg(nam,width=11,  height = 1.1*le)
  }
	for( i in 1:le){
		if(out[[i]][1,11]==-1){
		temp<-out[[i]]
		temp[,11]<-rep(1,nrow(temp))
		ma<-max(temp[,8])
		plus<-which(temp[,1]=="+")
		minus<-which(temp[,1]=="-")
		if(length(plus)>0){
			temp[plus,1]<-"-"
		}
		if(length(minus)>0){
			temp[minus,1]<-"+"
		}
			for(j in 1:nrow(temp)){
				temp[j,8]<-ma-out[[i]][j,7]
				temp[j,7]<-ma-out[[i]][j,8]
				temp[j,10]<-ma-out[[i]][j,9]
				temp[j,9]<-ma-out[[i]][j,10]
				}
			out[[i]]<-temp	
		}
		
	}
	
	#mas<-out[[1]][1,9]
	mas<-wind
	 for(i in 1:le){
		 te<-out[[i]]
		 s2<-mas-as.numeric(te[1,9])
		for(ii in 1:nrow(te)){
        
         
		 #print(as.numeric(te[1,9])[1])
        #s<-c(s,s2+mas)
         #se<-c(se,s2+mi)
         te[ii,7]<-as.numeric(te[ii,7])+s2
         te[ii,8]<-as.numeric(te[ii,8])+s2
         te[ii,9]<-as.numeric(te[ii,9])+s2
         te[ii,10]<-as.numeric(te[ii,10])+s2
         
		}
		out[[i]]<-te
     }
	
  #
  
  
  
  d_vect<-c()
  s_vect<-c()
  # for(i in 1:numb){
     #count2<-i*5
     #count2<-count2-5
    # mas<-c()
    # mi<-c()
    # for(ii in 1:5){
      # tryCatch({
        # te<-(out[[count2+ii]])
        # mas<-c(mas,max(as.numeric(te[,8])))
        # mi<-c(mi,min(as.numeric(te[,7])))

      # }, error=function(e){cat("ERROR :",conditionMessage(e), "\n")})
    # }
    # mas<-max(mas)
    # mi<-min(mi)
    # s<-c()
    # se<-c()
	
	
	
	
	
	
	
    
    # s<-max(s)
	# null<-which(se==0)
	# se<-min(se)
    # d_vect<-c(d_vect,s)	
    # s_vect<-c(s_vect,se)
  # }
  #for(jj in 1:le){
   # d<-d_vect[jj]
    #s<-s_vect[jj]
   #par(mar = c(-10, 5, -10, 5))
    #plot(1,1, type="n",xlim=c(s,d*1),ylim=c(0,5*5),xaxt="n",yaxt="n",xlab="",ylab="")	
	plot(1,1, type="n",xlim=c(1,wind*2),ylim=c(1,count),xaxt="n",yaxt="n",xlab="",ylab="", bty="n")
    for(i in 1:le){
     # if((i+(jj-1)*5)<=length(out)){
        temp<-out[[i]]

        mi<-min(as.numeric(temp[,7]))
        ma<-max(as.numeric(temp[,8]))

        lines(c(mi,ma),c(1+count-i*4,1+count-i*4))
        lines(c(mi,ma),c(2+count-i*4,2+count-i*4))
        for(j in 1:nrow(temp)){

          m<-(as.numeric(temp[j,8])-as.numeric(temp[j,7]))/2+as.numeric(temp[j,7])
          mm<-as.numeric(temp[j,8])-as.numeric(temp[j,7])
          n<--1
          if(temp[j,1]=="+"){
            n<-1
          }
          if(n==-1){
            n<-0
          }
          color<-"white"
          tcolor<-na.omit(grep(temp[j,5],cdhit_result))
          tcolor2<-na.omit(grep(temp[j,4],cdhit_result))
          tcolor<-c(tcolor,tcolor2)
          if(length(tcolor)>0){
             color<-names(cdhit_result)[tcolor]
           }
          rect(as.numeric(temp[j,7]),0.5+n+count-i*4,as.numeric(temp[j,8]),1.5+n+count-i*4, col=color)
          text(m,n+count-i*4+1+0.25,gsub("\"","",gsub("NA ","",gsub("orf.*","",temp[j,4]))),cex=0.4,font=4)
		  text(m,n+count-i*4+1-0.25,gsub("\"","",temp[j,5]),cex=0.4,font=4)
        }
        n<-as.numeric(temp[1,11])
        if(n==-1){
          n<-0
        }
        rect(as.numeric(temp[j,9]),0.5+n+count-i*4,as.numeric(temp[j,10]),1.5+n+count-i*4, col=2)
        text(wind,count-i*4,temp[j,12], cex=0.8, font=4)
       # count<-count-4
     # }		
    }
 dev.off()	

}

#plot_function4(out2[[1]],cd,wind=synteny_window,outformat="pdf", fasta=name)

# call mafft for MSA
mafft<-function(filename="ncrna.fa", outname="ncrna_aligned.fa", mode="fast"){
	if(mode=="accurate"){
		command<-paste("mafft --maxiterate 1000 --localpair --quiet --inputorder ", filename, " > ", outname, sep="" )
	}
	if(mode=="fast"){
		command<-paste("mafft --retree 2 --maxiterate 0 --quiet --inputorder ", filename, " > ", outname, sep="" )
	}
	if(mode=="very_fast"){
		command<-paste("mafft --retree 1 --maxiterate 0 --quiet --inputorder ", filename, " > ", outname, sep="" )
	}
	system(command)
} 

# function to exclude very similar organism based on a phylogentic tree to reduce complexity
exclude_similars<-function(dis, thres=0.01,ooi){
i<-1

o<-grep(ooi, rownames(dis))
nam<-colnames(dis)[o]
	temp<-which(dis[,o]<=thres)
	nam<-na.omit(match(nam, rownames(dis)))
	nam<-na.omit(match(nam, temp))
	if(length(nam)>0){
		temp<-temp[-nam]
	}
	
	if(length(temp)>0){
		dis<-dis[-temp,-temp]
		
	}
	



while(nrow(dis)>i){
	
	nam<-colnames(dis)[i]
	temp<-which(dis[,i]<=thres)
	nam<-na.omit(match(nam, rownames(dis)))
	nam<-na.omit(match(nam, temp))
	if(length(nam)>0){
		temp<-temp[-nam]
	}
	
	if(length(temp)>0){
		dis<-dis[-temp,-temp]
		
	}
	i<-i+1
}
dis
}



# Execute functions



fasta<-read.delim(filename, header=F, sep="\t")
fasta<-as.character(fasta[,1])
coor<-export_ncRNA_coordinates(fasta)

#if more than 1 homolog is detected for one organism or the same Refseq ID, keep only the homolog with the highest identity to the input
if(mixed_sources==F){
	iden<-gsub(".*VAL:","",coor[,"Full_header"])
	iden<-as.numeric(gsub("%.*","",iden))
	coor<-cbind(coor,iden)
	coor<-coor[order(iden, decreasing=T), ]
}


if(mixed_sources==T){
	mafft(filename=filename,outname="aligned_sRNA.fasta")
	dat<-read.phyDat("aligned_sRNA.fasta", format="fasta", type="DNA")
	dm <- dist.hamming(dat)
	dm<-as.matrix(dm)
	iden<-dm[,1]
	coor<-cbind(coor,iden)
	coor<-coor[order(iden, decreasing=F), ]
}
#coor<-coor[-1,] ##to remove the first sequence ########################### Apiwat's modification #################
if(duplicates_allowed==F){
	dup<-which(duplicated(coor[,1]))
	if(length(dup)>0){
	coor<-coor[-dup,]
	}
}

coor2<-coor
taxi<-gsub(".*taxID:","",coor[,"Full_header"])

# assign matching Refseq ID based on the Accesion Number
load(refpath)
fin<-match(coor[,1],ref[,1])
fin<-ref[fin,2]
coor<-cbind(coor,taxi,fin)

# remove entries with duplicated Refseq ID and entries without matching Refseq ID
if(duplicates_allowed==F){
	
		dup<-which(duplicated(fin))
		if(length(dup)>0){
			coor<-coor[-dup,]
			coor2<-coor2[-dup,]
		}
	
	
}

if(refseq_required==F){
	if(is.matrix(coor)==T){
			na<-which(is.na(coor[,"fin"]))
			if(length(na)>0){
				coor[na,"fin"]<-coor[na,"Accesion_number"]
			}
		}
}

# remove entries without Refseq ID
if(refseq_required==T){
	if(is.matrix(coor)==T){
		na<-which(is.na(coor[,"fin"]))
		if(length(na)>0){
			coor<-coor[-na,]
		}
	}
}

# keep only homologs represented in the coprarna reference file	

if(coprarna_compatible==T){
	copref<-read.delim(cop_path, sep="\t", header=T,comment.char = "#")	
		se<-function(x){
			out<-grep(x, copref[,1])[1]
			if(length(out)==0){
				out<-NA
			}
			out
		}
	notinlist<-which(is.na(unlist(lapply(gsub("\\..*","",coor[,"fin"]),se))))
	if(length(notinlist)>0){
		coor<-coor[-notinlist,]	
	}
}

# write fasta file with all sequences that have a assigned Refseq ID and are available for CopraRNA

# fasta3<-c()
		# for(i in 1:nrow(coor)){
			# fasta3<-c(fasta3, paste(">",coor[i,"fin"],"|",gsub(">","",coor[i,"Full_header"]),sep=""))
			# fasta3<-c(fasta3, as.character(coor[i,"sequence"]))
			
		# }
	

# write.table(fasta3, file=outfile, row.names=F, col.names=F, quote=F)


# create short names from organism name and Refseq ID

copref<-read.delim(cop_path, sep="\t", header=T,comment.char = "#")	
nam<-c()
for(i in 1:nrow(coor)){
	tnam<-grep(gsub("\\..*","",coor[i,"fin"]),copref[,1])
	nam<-c(nam,as.character(copref[tnam,2]))
	
	
}

nam2<-c()
for(i in 1:length(nam)){
	temp1<-substr(nam[i],1,3)
	temp2<-strsplit(nam[i],"_")[[1]]
	temp1<-paste(temp1,"_",temp2[2], sep="")
	if(length(temp2)>2){
		temp1<-paste(temp1, temp2[length(temp2)], sep="_")
	}
	nam2<-c(nam2,temp1)
}
nam2<-paste(nam2,coor[,"fin"], sep="_")

coor<-cbind(coor,nam2)

# extract information of sRNA gene neighborhood for synteny analysis and draw synteny pdf

save(coor, file="coor.Rdata")





if(reduced_svg==F){
	out2<-data_preparation_sqlite(coor,featpath=featpath, windo=synteny_window)




	tagtable<-locus_tag2org(out2)
	get_prot_fasta3(out2[[1]])
	cd<-cdhit_run(psi=F,thres=0.4)
	cd<-proc_cdhit(cd)


	plot_function4(out2[[1]],cd,wind=synteny_window,outformat="svg", fasta=name) #Apiwat's modification: ignore synteny image
}

#plot_function4(out2[[1]],cd,wind=synteny_window,outformat="cairo_pdf", fasta=name)

if(reduced_svg==TRUE){

d<-dir()
exist<-na.omit(match("full_tree.Rdata", d))

if(length(exist)==1){
	load("full_tree.Rdata")
	load("distances.Rdata")
}

if(length(exist)==0){

# retrive 16S rDNA sequences from a database 
	rRNA<-matrix(,nrow(coor),2)
	con <- dbConnect(SQLite(), dbname_16S, ":memory:")
	dbBegin(con)
	for(j in 1:nrow(coor)){
		#print(j)
		temp<-gsub("\\..*","",coor[j,1])
		temp<-paste("SELECT sequence   FROM 'rRNA_data' WHERE ID == '", temp,"'",sep="")
		#temp<-paste("SELECT sequence '  WHERE ID == '", temp,"'",sep="")
		temp<-dbGetQuery(con,temp )
		if(nrow(temp)>0){
			temp<-as.character(unlist(lapply(temp[[1]], memDecompress, asChar=T, type="gzip")))
			rRNA[j,2]<-as.character(temp)
			rRNA[j,1]<-coor[j,'fin']
		}
	}
	if(outorg!="internal"){
		rRNA<-rbind(rRNA, rep(NA,2))
		temp<-outorg
		temp<-paste("SELECT sequence   FROM 'rRNA_data' WHERE ID == '", temp,"'",sep="")
		#temp<-paste("SELECT sequence '  WHERE ID == '", temp,"'",sep="")
		temp<-dbGetQuery(con,temp )
		if(nrow(temp)>0){
			temp<-as.character(unlist(lapply(temp[[1]], memDecompress, asChar=T, type="gzip")))
			rRNA[nrow(rRNA),2]<-as.character(temp)
			rRNA[nrow(rRNA),1]<-outorg
		}
	}
	
	dbCommit(con)
	dbDisconnect(con)
	fasta<-c()
	for(j in 1:nrow(rRNA)){
		if(is.na(rRNA[j,1])==F){
			fasta<-c(fasta,paste(">", rRNA[j,1], sep=""),gsub("u","t",rRNA[j,2]))
		}
	}

	write.table(fasta, file="16s.fasta", row.names=F, col.names=F, quote=F)

	############################ Start of Apiwat's modification ###########################################
	### to make another 16s fasta file labeling by GenBank ID
	print('### Modified version by Apiwat ###')
	rRNA<-matrix(,nrow(coor),2)
	con <- dbConnect(SQLite(), dbname_16S, ":memory:")
	dbBegin(con)
	for(j in 1:nrow(coor)){
		#print(j)
		temp<-gsub("\\..*","",coor[j,1])
		temp<-paste("SELECT sequence   FROM 'rRNA_data' WHERE ID == '", temp,"'",sep="")
		#temp<-paste("SELECT sequence '  WHERE ID == '", temp,"'",sep="")
		temp<-dbGetQuery(con,temp )
		if(nrow(temp)>0){
			temp<-as.character(unlist(lapply(temp[[1]], memDecompress, asChar=T, type="gzip")))
			rRNA[j,2]<-as.character(temp)
			rRNA[j,1]<-coor[j,1]
		}
	}
	if(outorg!="internal"){
		rRNA<-rbind(rRNA, rep(NA,2))
		temp<-outorg
		temp<-paste("SELECT sequence   FROM 'rRNA_data' WHERE ID == '", temp,"'",sep="")
		#temp<-paste("SELECT sequence '  WHERE ID == '", temp,"'",sep="")
		temp<-dbGetQuery(con,temp )
		if(nrow(temp)>0){
			temp<-as.character(unlist(lapply(temp[[1]], memDecompress, asChar=T, type="gzip")))
			rRNA[nrow(rRNA),2]<-as.character(temp)
			rRNA[nrow(rRNA),1]<-outorg
		}
	}
	
	dbCommit(con)
	dbDisconnect(con)
	fasta<-c()
	for(j in 1:nrow(rRNA)){
		if(is.na(rRNA[j,1])==F){
			fasta<-c(fasta,paste(">", rRNA[j,1], sep=""),gsub("u","t",rRNA[j,2]))
		}
	}

	write.table(fasta, file="16s_GenBank.fasta", row.names=F, col.names=F, quote=F)

	############################ End of Apiwat's modification ###########################################

	mafft(filename="16s.fasta",outname="16s_aligned.fasta")

	# create a ML tree based on the alignment
	tempf<-read.fasta("16s_aligned.fasta")
	write.fasta(tempf, file.out="16s_aligned.fasta", names=names(tempf), nbchar=100000)
	dat<-read.phyDat("16s_aligned.fasta", format="fasta", type="DNA")
	dm <- dist.ml(dat, model="F81")
	dm2<-as.matrix(dm)
	save(dm2, file="distances.Rdata")
	p3<-exclude_similars(dm2, mindis,ooi=ooi)
	
	treeNJ <- NJ(dm)
	#tree <- pratchet(dat)          # parsimony tree
	#tree <- nnls.phylo(tree, dm)

	#fitStart = pml(treeNJ, dat, k=4)
	#fitJC = optim.pml(fitStart, model="GTR", optGamma=TRUE, rearrangement="none")
	#treeNJ<-tree
	fitJC = pml(treeNJ, data=dat)
	#fitJC = treeNJ
	#fitJC<-optim.pml(fitJC, model="GTR", optInv=TRUE, optGamma=TRUE, rearrangement = "stochastic", control = pml.control(trace = 0))
	fit2<-fitJC
	fitJC<-fit2
	lab<-fitJC$tree$tip.label
	lab2<-lab

	save(fitJC, file="full_tree.Rdata") 
	
}	
 p<-cophenetic(fitJC$tree)

#p<-cophenetic(fitJC)


# exclude organsims that are too similar to each other 
p3<-exclude_similars(p, mindis,ooi=ooi)



coor3<-coor[match(colnames(p3),coor[,"fin"]),]
out2<-data_preparation_sqlite(coor3,featpath=featpath, windo=synteny_window)




tagtable<-locus_tag2org(out2)
get_prot_fasta3(out2[[1]])
cd<-cdhit_run(psi=F,thres=0.6)
cd<-proc_cdhit(cd)
plot_function4(out2[[1]],cd,wind=synteny_window,outformat="pdf", fasta=name)

}

#unlink("protein_fasta.txt") #Apiwat's modification ########## to remove gene neighborhood sequence fasta
 cluster_table<-function(cd){
	out<-c()
	for( i in 1:length(cd)){
		temp<-paste(cd[[i]], collapse=",")
		out<-c(out,temp)
	}
	names(out)<-paste("cluster_",1:length(out),sep="")
	out
}

cluster<-cluster_table(cd)
write.table(cluster, file=paste(name,"cluster_table.txt",sep="_"), sep="\t", quote=F)
# write 16S sequences to fasta file 
 
synt_table<-function(out3, coor){
	res<-matrix(,length(out3),6)
	colnames(res)<-c("ID","organism","accesion","refseqID","neighbourhood_genes","position2sRNA")
	for(i in 1:length(out3)){
		tmp<-out3[[i]][order(out3[[i]][,"aa"]),]
		pos<-which(tmp[,"aa"]<tmp[,"rep(s_srna, nrow(temp_out))"])
		pos2<-seq(1,nrow(tmp)-length(pos))
		pos<-c(rev(pos),pos2)
		res[i,1]<-names(out3)[i]
		res[i,2]<-coor[match(gsub("_.*","",names(out3)[i]), coor[,1]),"name"]
		res[i,3]<-coor[match(gsub("_.*","",names(out3)[i]), coor[,1]),1]
		res[i,4]<-coor[match(gsub("_.*","",names(out3)[i]), coor[,1]),"fin"]
		#res[i,5]<-paste(gsub("\"","",out3[[i]][,"locus_tag"]),collapse=",")
		res[i,5]<-paste(gsub("\"","",tmp[,"locus_tag"]),collapse=",")
		res[i,6]<-paste(pos,collapse=",")
	}
	res
}
 
synteny<-synt_table(out2[[1]],coor)
write.table(synteny, file=paste(name,"synteny_table.txt",sep="_"), sep="\t", quote=F, row.names=F)

############################ Apiwat modification ######################################
synt_table<-function(out3, coor){
	res<-matrix(,length(out3),6)
	colnames(res)<-c("ID","organism","accesion","refseqID","neighbourhood_genes","position2sRNA")

	fasta3<-c()
	for(i in 1:length(out3)){
		tmp<-out3[[i]][order(out3[[i]][,"aa"]),]
		pos<-which(tmp[,"aa"]<tmp[,"rep(s_srna, nrow(temp_out))"])
		pos2<-seq(1,nrow(tmp)-length(pos))
		pos<-c(rev(pos),pos2)
		res[i,1]<-names(out3)[i]
		res[i,2]<-coor[match(gsub("_.*","",names(out3)[i]), coor[,1]),"name"]
		res[i,3]<-coor[match(gsub("_.*","",names(out3)[i]), coor[,1]),1]
		res[i,4]<-coor[match(gsub("_.*","",names(out3)[i]), coor[,1]),"fin"]
		#res[i,5]<-paste(gsub("\"","",out3[[i]][,"locus_tag"]),collapse=",")
		res[i,5]<-paste(gsub("\"","",tmp[,"locus_tag"]),collapse=",")
		res[i,6]<-paste(pos,collapse=",")

		fasta3<-c(fasta3, paste(coor[match(gsub("_.*","",names(out3)[i]), coor[,1]),"Full_header"],sep=""))
		fasta3<-c(fasta3, as.character(coor[match(gsub("_.*","",names(out3)[i]), coor[,1]),"sequence"]))


	}
	write.table(fasta3, file='pass_glassgo2copra.fasta', row.names=F, col.names=F, quote=F)
	res
}
 
synteny<-synt_table(out2[[1]],coor)
write.table(synteny, file=paste(name,"synteny_table.txt",sep="_"), sep="\t", quote=F, row.names=F)

############################ End of Apiwat modification ######################################

#######################
#######################
#######################


selection<-function( maxorgs,mindis,maxdis,closeorgs,cluster_thres,ooi, name="sRNA",min_size, outorg="U00096",full_tree=F, wildcard=c()){ 

load("coor.Rdata")
# put ooi to the first row of the "coor" table
#ooip<-grep(ooi, coor[,"fin"])
#coor<-coor[c(ooip,seq(1,nrow(coor))[-ooip]),]
#coor2<-coor


d<-dir()
exist<-na.omit(match("full_tree.Rdata", d))

if(length(exist)==1){
	load("full_tree.Rdata")
	load("distances.Rdata")
}

if(length(exist)==0){
	# retrive 16S rDNA sequences from a database 
	rRNA<-matrix(,nrow(coor),2)
	con <- dbConnect(SQLite(), dbname_16S, ":memory:")
	dbBegin(con)
	for(j in 1:nrow(coor)){
		#print(j)
		temp<-gsub("\\..*","",coor[j,1])
		temp<-paste("SELECT sequence   FROM 'rRNA_data' WHERE ID == '", temp,"'",sep="")
		#temp<-paste("SELECT sequence '  WHERE ID == '", temp,"'",sep="")
		temp<-dbGetQuery(con,temp )
		if(nrow(temp)>0){
			temp<-as.character(unlist(lapply(temp[[1]], memDecompress, asChar=T, type="gzip")))
			rRNA[j,2]<-as.character(temp)
			rRNA[j,1]<-coor[j,"fin"]
			#rRNA[j,1]<-coor[j,1] #Refseq acc label in 16s fasta file
		}
	}
	if(outorg!="internal"){
		rRNA<-rbind(rRNA, rep(NA,2))
		temp<-outorg
		temp<-paste("SELECT sequence   FROM 'rRNA_data' WHERE ID == '", temp,"'",sep="")
		#temp<-paste("SELECT sequence '  WHERE ID == '", temp,"'",sep="")
		temp<-dbGetQuery(con,temp )
		if(nrow(temp)>0){
			temp<-as.character(unlist(lapply(temp[[1]], memDecompress, asChar=T, type="gzip")))
			rRNA[nrow(rRNA),2]<-as.character(temp)
			rRNA[nrow(rRNA),1]<-outorg
		}
	}
	
	dbCommit(con)
	dbDisconnect(con)
	fasta<-c()
	for(j in 1:nrow(rRNA)){
		if(is.na(rRNA[j,1])==F){
			fasta<-c(fasta,paste(">", rRNA[j,1], sep=""),gsub("u","t",rRNA[j,2]))
		}
	}

	write.table(fasta, file="16s.fasta", row.names=F, col.names=F, quote=F)

	############################ Start of Apiwat's modification ###########################################
	### to make another 16s fasta file labeling by GenBank ID

	rRNA<-matrix(,nrow(coor),2)
	#rRNA_GenBank<-matrix(,nrow(coor),2)
	con <- dbConnect(SQLite(), dbname_16S, ":memory:")
	dbBegin(con)
	for(j in 1:nrow(coor)){
		#print(j)
		temp<-gsub("\\..*","",coor[j,1])
		temp<-paste("SELECT sequence   FROM 'rRNA_data' WHERE ID == '", temp,"'",sep="")
		#temp<-paste("SELECT sequence '  WHERE ID == '", temp,"'",sep="")
		temp<-dbGetQuery(con,temp )
		if(nrow(temp)>0){
			temp<-as.character(unlist(lapply(temp[[1]], memDecompress, asChar=T, type="gzip")))
			rRNA[j,2]<-as.character(temp)

			#rRNA[j,1]<-coor[j,"fin"] #Refseq acc label in 16s fasta file
			rRNA[j,1]<-coor[j,1] #Refseq acc label in 16s fasta file
		}
	}
	if(outorg!="internal"){
		rRNA<-rbind(rRNA, rep(NA,2))
		temp<-outorg
		temp<-paste("SELECT sequence   FROM 'rRNA_data' WHERE ID == '", temp,"'",sep="")
		#temp<-paste("SELECT sequence '  WHERE ID == '", temp,"'",sep="")
		temp<-dbGetQuery(con,temp )
		if(nrow(temp)>0){
			temp<-as.character(unlist(lapply(temp[[1]], memDecompress, asChar=T, type="gzip")))
			rRNA[nrow(rRNA),2]<-as.character(temp)
			rRNA[nrow(rRNA),1]<-outorg
		}
	}
	
	dbCommit(con)
	dbDisconnect(con)
	fasta<-c()

	for(j in 1:nrow(rRNA)){
		if(is.na(rRNA[j,1])==F){
			fasta<-c(fasta,paste(">", rRNA[j,1], sep=""),gsub("u","t",rRNA[j,2]))
		}
	}
	write.table(fasta, file="16s_GenBank.fasta", row.names=F, col.names=F, quote=F)
	############################ End of Apiwat's modification ###########################################

	mafft(filename="16s.fasta",outname="16s_aligned.fasta")

	# create a ML tree based on the alignment
	tempf<-read.fasta("16s_aligned.fasta")
	write.fasta(tempf, file.out="16s_aligned.fasta", names=names(tempf), nbchar=100000)
	dat<-read.phyDat("16s_aligned.fasta", format="fasta", type="DNA")
	dm <- dist.ml(dat, model="F81")
	dm2<-as.matrix(dm)
	save(dm2, file="distances.Rdata")
	p3<-exclude_similars(dm2, mindis,ooi=ooi)
	
	treeNJ <- NJ(dm)
	#tree <- pratchet(dat)          # parsimony tree
	#tree <- nnls.phylo(tree, dm)

	#fitStart = pml(treeNJ, dat, k=4)
	#fitJC = optim.pml(fitStart, model="GTR", optGamma=TRUE, rearrangement="none")
	#treeNJ<-tree
	fitJC = pml(treeNJ, data=dat)
	#fitJC = treeNJ
	#fitJC<-optim.pml(fitJC, model="GTR", optInv=TRUE, optGamma=TRUE, rearrangement = "stochastic", control = pml.control(trace = 0))
	fit2<-fitJC
	fitJC<-fit2
	lab<-fitJC$tree$tip.label
	lab2<-lab

	save(fitJC, file="full_tree.Rdata")
}
if(outorg=="internal"){
	ooip2<-grep(ooi,colnames(dm2))
	outorg<-names(sort(dm2[,ooip2])[nrow(dm2)])
}
p<-cophenetic(fitJC$tree)

#p<-cophenetic(fitJC)


# exclude organsims that are too similar to each other 
p3<-exclude_similars(p, mindis,ooi=ooi)

 # while(nrow(p3)>150){
	 # mindis<-mindis+0.0001
	 # p3<-exclude_similars(p, mindis,ooi=ooi)
# }



if(nrow(p)>=maxorgs){
	while(nrow(p3)<maxorgs){
		mindis<-mindis-mindis/100
		p3<-exclude_similars(p, mindis,ooi=ooi)
	}
}



ooip<-grep(ooi,colnames(p3))
#outorg<-names(sort(p3[,ooip])[nrow(p3)])
if(length(ooip)==0){
	print("organism of interest is not detected in input data")
	break
}

# exclude too distant organisms regarding to the ooi

ma<-which(p3[,ooip]>maxdis)
# outorg_pos<-match(outorg,names(ma))
# if(length(outorg_pos)>0){
	# ma<-ma[-outorg_pos]
# }

if(length(ma)>0){
	p5<-p3[-ma,-ma]	
	
}

#outorg<-names(sort(p3[,ooip])[nrow(p3)])
ooip<-grep(ooi,colnames(p3))

if(nrow(p3)>=maxorgs ){
	while(nrow(p5)<maxorgs & length(ma)>0){
		maxdis<-maxdis+0.001
		ma<-which(p3[,ooip]>maxdis)
		p5<-p3[-ma,-ma]
	}
}


p4<-p3
# n<-1
# while(sum(n)<maxorgs){
	# n<-c(n,n[length(n)]+1)
# }

# if((maxorgs-sum(n))>0){
	# n<-c(maxorgs-sum(n),n)
# }

# n<-sort(n)
# n<-rev(n)
# groupsize<-floor(nrow(p4)/(length(n)*2))

# pos_orgs<-sort(p4[,1])[-1]
# sel<-c()
# for(i in 1:length(n)){
	# temp<-sample( groupsize,n[i])
	# temp<-temp+(i-1)*groupsize
	# sel<-c(sel,names(pos_orgs)[temp])
# }

wild<-c()
if(length(wildcard)>0){
	for(i in 1:length(wildcard)){
		wild<-c(wild,grep(wildcard[i], colnames(p)))
	}
	wild<-colnames(p)[wild]
}


orglist<-unique(c(colnames(p3),outorg,wild))
#orglist<-unique(c(colnames(p3),outorg))
# tree based on organisms in p4
fasta2<-read.fasta("16s.fasta")
dm2<-match(orglist,names(fasta2))
tempf2<-fasta2[dm2]
write.fasta(tempf2, file.out="16s_subset.fasta", names=names(tempf2), nbchar=100000)
mafft(filename="16s_subset.fasta",outname="16s_aligned2.fasta", mode="fast")
dat<-read.phyDat("16s_aligned2.fasta", format="fasta", type="DNA")
#dm <- dist.ml(dat, model="F81", exclude = "all")

dm <- dist.ml(dat, model="F81")

treeNJ <- NJ(dm)
fitStart = pml(treeNJ, dat, k=4)
fitJC = optim.pml(fitStart, model="GTR", optGamma=T, rearrangement="stochastic",ratchet.par = list(iter = 5L, maxit = 20L, prop = 1/3),control = pml.control(epsilon = 1e-08, maxit = 10,
  trace = 1L))
#fitJC = pml(treeNJ, data=dat)
fit2<-fitJC
fitJC<-fit2
lab<-fitJC$tree$tip.label
lab2<-lab



tree<-root(fitJC$tree, outgroup=outorg, resolve.root = TRUE)
lab<-tree$tip.label
lab2<-lab
#tree<-midpoint(fitJC$tree)
#tree<-(fitJC$tree)


p_new<-cophenetic(tree)


sum_of_branches<-function(node, tree, normalized=TRUE){  # sum of branch length from all branches to specified inner node
	topo<-tree[[1]]
	branch<-tree[[2]]
	names(node)<-1
	out<-node
	edge<-c()
	nn<-node
	temp<-c()
	#weight<-c()
	
	while(1>0){
		na<-as.numeric(names(nn))
		n<-which(topo[,1]==nn)
		names(n)<-rep(na,length(n))
		edge<-c(edge,n)
		temp_node<-topo[n,2]
		node<-setdiff(temp_node, node)
		names(node)<-rep(na+1,length(node))
		out<-c(out,node)
		temp<-na.omit(c(temp,node[2:length(node)]))
		nn<-node[1]
		if(is.na(nn)==T & length(temp)>0){
			nn<-temp[1]
			temp<-temp[-1]
		}
		if(is.na(nn)==T & length(temp)==0){
			#print("ff")
			break
			
		}
	}
	dup<-which(duplicated(edge))
	if(length(dup)>0){
		edge<-edge[-dup]
	}
	
	sob<-sum(branch[edge])
	out<-na.omit(out)
	out<-out[which(is.element(out,topo[,1])==F)]
	if(normalized==TRUE){
		sob<-branch[edge]
		#sob<-sum(sob/as.numeric(names(edge)))
		sob<-sum(sob)
		if(length(out)>0){
			sob<-sob/length(out)
		}
	}
	sob
	
}


leafs<-function(node, tree){  # finds leafs belonging to an inner node
	topo<-tree[[1]]
	branch<-tree[[2]]
	names(node)<-1
	out<-node
	edge<-c()
	nn<-node
	temp<-c()
	#weight<-c()
	
	while(1>0){
		na<-as.numeric(names(nn))
		n<-which(topo[,1]==nn)
		names(n)<-rep(na,length(n))
		edge<-c(edge,n)
		temp_node<-topo[n,2]
		node<-setdiff(temp_node, node)
		names(node)<-rep(na+1,length(node))
		out<-c(out,node)
		temp<-na.omit(c(temp,node[2:length(node)]))
		nn<-node[1]
		if(is.na(nn)==T & length(temp)>0){
			nn<-temp[1]
			temp<-temp[-1]
		}
		if(is.na(nn)==T & length(temp)==0){
			#print("ff")
			break
			
		}
	}
	dup<-which(duplicated(edge))
	if(length(dup)>0){
		edge<-edge[-dup]
	}
	
	sob<-sum(branch[edge])
	out<-na.omit(out)
	out<-out[which(is.element(out,topo[,1])==F)]
	out
	
}


cut_tree<-function(childs, topo,branch,clustervalue){
	cu<-c()
	for(i in 1:length(childs)){
		inner<-topo[which(topo[,2]==childs[i]),1]
		edge_inner<-topo[grep(inner,topo[,1]),2]
		edge_inner<-match(edge_inner,topo[,2])
		edge_inner<-sum(branch[edge_inner])
		sobs<-sum_of_branches(childs[i],tree,normalized=T)
		#print(c(i,childs[i],sobs[i]/edge_inner ))
		if(sobs/edge_inner <clustervalue){
			cu<-c(cu, childs[i])
		}
	}
	cu
}
(fitJC$tree)


d_all<-dist.nodes(tree)

cut_tree2<-function(childs, tree,d_all,leafs1,FC_thres=1, p_thres=0.01){
	FC_thres<-abs(log2(FC_thres))
#cut_tree2<-function(childs, tree,d_all,leafs1,clustervalue=0.1){
	cu<-c()
	cu2<-c()
	topo<-tree[[1]] # tree topology
	branch<-tree[[2]]
	for(i in 1:length(childs)){
		print(i)
		first_inner<-topo[which(topo[,1]==childs[i]),2]
		isleaf<-which(is.element(first_inner,leafs1))
		if(length(isleaf)==0){
			leaf2<-vector("list",length(first_inner))
			for(j in 1:length(first_inner)){
				
				tmp<-leafs(first_inner[j], tree)
				tmp<-d_all[as.character(childs[i]),as.character(tmp)]
				if(length(tmp)==1){
					tmp<-rep(tmp,2)
				}
				leaf2[[j]]<-tmp
			}
			test<-t.test(leaf2[[1]],leaf2[[2]])
			
			if(test$p.value<=p_thres & abs(log2(mean(leaf2[[1]])/mean(leaf2[[2]])))>=FC_thres){
				cu<-c(cu, first_inner)
				cu2<-c(cu2, childs[i])
				print(c(test$p.value,log2(mean(leaf2[[1]])/mean(leaf2[[2]]))))
				
			}
		}
		if(length(isleaf)==1){
			inner<-first_inner[-isleaf]
			tmp<-leafs(inner, tree)
			tmp<-d_all[as.character(inner),as.character(tmp)]
			tmp<-mean(tmp)
			edge1<-d_all[as.character(childs[i]),as.character(first_inner[isleaf])]
			edge2<-d_all[as.character(childs[i]),as.character(first_inner[-isleaf])]
			rat<-tmp/(edge1+edge2)
			if(abs(log2(rat))>=FC_thres*1.5){
				cu<-c(cu, first_inner[-isleaf])
				cu2<-c(cu2, childs[i])
			}
					
		}
		
	}
	return(list(cu,cu2))
}





cut_tree3<-function(childs, tree,d_all,leafs1,thres=1, penalty_number=3, penalty=5,mindis){
	#FC_thres<-abs(log2(FC_thres))
#cut_tree2<-function(childs, tree,d_all,leafs1,clustervalue=0.1){
	cu<-c()
	cu2<-c()
	topo<-tree[[1]] # tree topology
	branch<-tree[[2]]
	for(i in 1:length(childs)){
		#print(i)
		first_inner<-topo[which(topo[,1]==childs[i]),2]
		isleaf<-which(is.element(first_inner,leafs1))
		# if(length(isleaf)>0){
			# first_inner<-first_inner[-isleaf]
		# }
		
		# print(length(first_inner))
		if(length(isleaf)==0){
			norm<-rep(NA,length(first_inner))
			edges<-norm
			names(norm)<-first_inner
			names(edges)<-first_inner
			leaf2<-vector("list",length(first_inner))
			for(j in 1:length(first_inner)){
				
				tmp<-unname(leafs(first_inner[j], tree))
				#tmp<-d_all[as.character(childs[i]),as.character(tmp)]
				#if(length(tmp)==1){
				#	tmp<-rep(tmp,2)
				#}
				leaf2[[j]]<-tmp
			}
			pen<-rep(FALSE,2)
			for(j in 1:length(leaf2)){
				leaf_inner<-c()
				norm_length<-c()
				for(ii in 1:length(leaf2[[j]])){
						tmp<-topo[which(topo[,2]==leaf2[[j]][ii]),1]
						leaf_inner<-c(leaf_inner,tmp)
						norm_length<-c(norm_length,d_all[as.character(tmp),as.character(leaf2[[j]][ii])])
				}
				two_leafs<-which(duplicated(leaf_inner))
				
				if(length(leaf_inner)<=penalty_number){
					pen[j]<-TRUE
				}
				while(length(two_leafs)>0 & leaf_inner[two_leafs[1]]!=first_inner[j]){
				#print(leaf_inner)
					del<-c()
					new_li<-c()
					new_nle<-c()
					for(ii in 1:length(two_leafs)){
						tmp<-which(leaf_inner==leaf_inner[two_leafs[ii]])
						tmp_le<-mean(norm_length[tmp])
						del<-c(del,tmp)
						new_li<-c(new_li,topo[which(topo[,2]==leaf_inner[two_leafs[ii]]),1])
						new_nle<-c(new_nle,tmp_le)
					}
					leaf_inner<-leaf_inner[-del]
					norm_length<-norm_length[-del]
					leaf_inner<-c(leaf_inner,new_li)
					norm_length<-c(norm_length,new_nle)
					two_leafs<-which(duplicated(leaf_inner))
					
				}
				norm[j]<-mean(norm_length)
				edges[j]<-d_all[as.character(childs[i]),as.character(first_inner[j])]
			}
			
			
			
			for(j in 1:length(edges)){
				#print(norm[j]/(edges[j]+edges[-j]))
				no<-norm[j]
				no2<-no
				if(pen[j]==T){
					no<-no*penalty
				}
				if(no/(edges[j]+edges[-j])<=thres & no2+edges[j]>mindis){
				#print(norm[j]/(edges[j]+edges[-j]))
					cu<-c(cu, first_inner[j])
					#cu<-c(cu, first_inner)
					cu2<-c(cu2, childs[i])
				}
			}
			
		}
		if(length(isleaf)==1){
			norm<-rep(NA,length(first_inner))
			edges<-norm
			names(norm)<-first_inner
			names(edges)<-first_inner
			leaf2<-vector("list",length(first_inner))
			for(j in 1:length(first_inner)){
				
				tmp<-unname(leafs(first_inner[j], tree))
				#tmp<-d_all[as.character(childs[i]),as.character(tmp)]
				#if(length(tmp)==1){
				#	tmp<-rep(tmp,2)
				#}
				leaf2[[j]]<-tmp
			}
			pen<-rep(FALSE,2)
			for(j in 1:length(leaf2)){
				leaf_inner<-c()
				norm_length<-c()
				for(ii in 1:length(leaf2[[j]])){
						tmp<-topo[which(topo[,2]==leaf2[[j]][ii]),1]
						leaf_inner<-c(leaf_inner,tmp)
						norm_length<-c(norm_length,d_all[as.character(tmp),as.character(leaf2[[j]][ii])])
				}
				two_leafs<-which(duplicated(leaf_inner))
				if(length(leaf_inner)<=penalty_number){
					pen[j]<-TRUE
				}
				while(length(two_leafs)>0 & leaf_inner[two_leafs[1]]!=first_inner[j]){
				#print(leaf_inner)
					del<-c()
					new_li<-c()
					new_nle<-c()
					for(ii in 1:length(two_leafs)){
						tmp<-which(leaf_inner==leaf_inner[two_leafs[ii]])
						tmp_le<-mean(norm_length[tmp])
						del<-c(del,tmp)
						new_li<-c(new_li,topo[which(topo[,2]==leaf_inner[two_leafs[ii]]),1])
						new_nle<-c(new_nle,tmp_le)
					}
					leaf_inner<-leaf_inner[-del]
					norm_length<-norm_length[-del]
					leaf_inner<-c(leaf_inner,new_li)
					norm_length<-c(norm_length,new_nle)
					two_leafs<-which(duplicated(leaf_inner))
					
				}
				norm[j]<-mean(norm_length)
				edges[j]<-d_all[as.character(childs[i]),as.character(first_inner[j])]
			}
			
			
			
				no<-norm[-isleaf]
				no2<-no
				if(pen[-isleaf]==T){
					no<-no*penalty
				}
				#print(norm[j]/(edges[j]+edges[-j]))
				if(no/min(edges[-isleaf]*2,edges[isleaf])<=thres & no2+edges[-isleaf]>mindis){
				#print(norm[j]/(edges[j]+edges[-j]))
					cu<-c(cu, first_inner[-isleaf])
					cu2<-c(cu2, childs[i])
				}
			
			
		}
		
		
		
	}
	return(list(cu,cu2))
}




#cluster_tree<-function(tree){
	topo<-tree[[1]] # tree topology
	branch<-tree[[2]]	
	root<-setdiff(topo[,1],topo[,2])
	leafs1<-setdiff(topo[,2],topo[,1])
	childs<-setdiff(topo[,1],root)
	#cu<-c()
	#tmp<-cut_tree3(topo[,1],tree,d_all,leafs1,thres=0.8,penalty_number=4,mindis=0.005*3) # smaller = more strict
	tmp<-cut_tree3(topo[,1],tree,d_all,leafs1,thres=cluster_thres,penalty_number=min_size,penalty=4,mindis=0.01) # smaller = more strict
	cu<-tmp[[1]]
	cu2<-tmp[[2]]
			

cu<-unique(c(root,cu))
cu2<-unique(cu2)
leaf<-list()

for(i in 1:(length(cu))){
	leaf[[length(leaf)+1]]<-unname(leafs(cu[i],tree))
	#tmp<-topo[grep(cu[i],topo[,2]),1]
	#leaf[[length(leaf)+1]]<-leafs(tmp,tree)
}

names(leaf)<-cu
le<-unlist(lapply(leaf,length))
leaf<-leaf[order(le)]

#leaf<-rev(leaf)


for(i in 1:(length(leaf)-1)){
	
	temp<-unname(unlist(leaf[i]))
	for(j in (i+1):(length(leaf))){
		leaf[[j]]<-setdiff(leaf[[j]],temp)	
	}
}
	
 empty<-c()
for(i in 1:length(leaf)){
	if(length(leaf[[i]])==0){
		empty<-c(empty,i)
	}
}
if(length(empty)>0){
	leaf<-leaf[-empty]
}	
	
	




pastef<-function(x){
	return(paste("i",x,"i"))
}

find_leaf<-function(x){
	out<-grep(paste("i",x,"i"),lapply(leaf,pastef))
	out
}
#leaf2<-leaf
# for(i in 1:length(leaf)){
	# leaf2[[i]]<-fitJC$tree$tip.label[leaf[[length(leaf)-i+1]]]
ooip_tree<-grep(ooi, tree$tip.label)
ooi_leaf<-grep(paste("i",ooip_tree,"i"),lapply(leaf,pastef))


near_orgs<-which(p3[,ooip]<=maxdis)
near_orgs<-match(colnames(p3)[near_orgs],colnames(p_new))
near_dis<-max(p_new[grep(ooi,colnames(p_new)),near_orgs])
near_orgs<-colnames(p_new)[which(p_new[,ooip]<=near_dis)]

near_orgs<-match(near_orgs,lab2)



near_leafs<-unique(unlist(lapply(near_orgs,find_leaf)))

ooi_leaf<-names(leaf)[ooi_leaf]

#leaf2<-leaf2[near_leafs]

#leaf2<-leaf2[near_leafs]

if(full_tree==F){
	leaf<-leaf[near_leafs]
}


leaf_le<-unlist(lapply(leaf,length))

if(length(leaf)>1){
	while(min(leaf_le)<min_size){
		ca<-names(leaf)[which(leaf_le<min_size)[1]]
		s<-sort(d_all[ca,names(leaf)])
		tmp<-c(leaf[[ca]],leaf[[names(s)[2]]])
		ca2<-names(s)[2]
		new_na<-names(sort(d_all[ooip_tree,c(ca,ca2)]))[2]
		
		leaf<-leaf[-match(c(ca,ca2),names(leaf))]
		leaf[[length(leaf)+1]]<-tmp
		names(leaf)[length(leaf)]<-new_na
		leaf_le<-unlist(lapply(leaf,length))
	}
}

if(full_tree==F){
	leaf_dis<-(d_all[names(leaf),ooi_leaf])
	leaf<-leaf[order(leaf_dis)]
	leaf_order<-names(sort(leaf_dis))



	if(length(near_orgs)>=maxorgs & length(unlist(leaf))<maxorgs){
		tmp<-setdiff(near_orgs,unlist(leaf))
		leaf[[length(leaf)+1]]<-tmp
	}
}
leaf2<-leaf
for(i in 1:length(leaf)){
	leaf2[[i]]<-fitJC$tree$tip.label[leaf[[i]]]
	
}


sel<-c()
if(full_tree==T){
	sel<-wild
	exist<-match(wild, tree$tip.label)
	n<-floor(maxorgs/length(leaf))
	more<-maxorgs-n*length(leaf)
	gr<-rep(n,length(leaf))
	wild_leaf<-c()
	for(i in 1:length(wild)){
		wild_leaf<-c(wild_leaf,grep(paste("i",exist[i],"i"),lapply(leaf,pastef)))
	}
	wild_leaf<-names(leaf)[wild_leaf]
	wild_leaf<-c(wild_leaf,names(rev(sort(leaf_le)))[1:(more-length(wild))])
	gr[match(wild_leaf,names(leaf))]<-gr[match(wild_leaf,names(leaf))]+1
	for(i in 1:length(leaf)){
		exist2<-na.omit(match(wild,leaf2[[i]]))
		n_temp<-gr[i]-length(exist2)
		n_temp<-min(n_temp,length(leaf[[i]]))
		if(length(n_temp)>0){
			tmp<-setdiff(leaf2[[i]],sel)
			n_temp<-min(n_temp, tmp)
			tmp<-sample(tmp,n_temp)
			#tmp<-tree$tip.label[tmp]
			sel<-c(sel,tmp)
		}
	}
	sel<-unique(sel)

}


if(full_tree==F){
	if(nrow(p_new)>maxorgs){
		# while(length(leaf[[1]])<closeorgs+1 ){
			# sel<-c(sel,lab[leaf[[1]]][min(closeorgs,length(leaf[[1]])) ])
			# closeorgs<-closeorgs-length(leaf[[1]])
			# leaf[[1]]<-c(leaf[[1]],leaf[[2]])
			# leaf<-leaf[-2]
			
		# }
		
		if(length(leaf)==1){
			sel<-divide(maxorgs,leaf[[1]],p4=p_new)
			# b<-floor(length(leaf[[1]])/maxorgs)
			# more<-maxorgs-b*length(leaf[[1]])
			# sel<-seq(1,b*length(leaf[[1]]),by=b)
			# cands<-names(sort(p4[leaf[[1]],1]))
			# sel<-cands[sel]
			# if(more>0){
				# r<-setdiff(cands,sel)
				# sel<-c(sel,r[1:more])
			# }
		}
		
		if(length(leaf)>1){
			#sel2<-names(sort(p4[leaf[[1]],1]))[seq(1,min(length(leaf[[1]])-1,closeorgs*2),by=min(length(leaf[[1]])-1,floor(closeorgs*2)/closeorgs))+1]
			rest<-maxorgs-closeorgs-1
			
			
			gr<-floor(rest/(length(leaf)-1))
			more<-rest-gr*(length(leaf)-1)
			gr<-rep(gr,(length(leaf)-1))
			count<-1
			while(more>0){
				gr[count]<-gr[count]+1
				count<-count+1
				more<-more-1
				if(count>length(gr)){
					count<-1
				}
			}
			
			gr<-c(closeorgs+1,gr)
			#leaf2<-leaf[-1]
			le<-unlist(lapply(leaf,length))
			small<-which(le<gr)
			while(length(small)>0){
				for(i in 1:length(small)){
					a<-1#gr[small[i]]-le[small[i]]
					gr[small[i]]<-gr[small[i]]-a
					cl<-which((gr+a)<=le)
					cl2<-cl[which(cl>small[i])]
					if(length(cl2)==0){
						cl2<-cl[which(cl<small[i])]
						cl2<-cl2[length(cl2)]
					}
					if(length(cl2)>0){
						cl2<-cl2[1]
					}
					gr[cl2]<-gr[cl2]+a
				
				small<-which(le<gr)
				}
			
			}
			
		for(i in 1:length(leaf)){
		#print(i)
			if(gr[i]>0){
				if(i==1){
					tmp<-divide(gr[i],leaf[[i]],p4=p_new,max_step=3,ooi=ooi)	
					sel<-c(sel, tmp)
				}
				if(i>1){
					tmp<-divide(gr[i],leaf[[i]],p4=p_new,max_step=5,ooi=ooi)	
					sel<-c(sel, tmp)
				}
			}

		}
		
		}
		
		
	}
	sel<-unique(sel)
	if(nrow(p_new)<=maxorgs){
		sel<-colnames(p_new)
	}

}

ooi<-coor[grep(ooi,coor[,"fin"]),"fin"]
sel<-unique(c(ooi,sel))
color = grDevices::colors()[grep('gr(a|e)y', grDevices::colors(), invert = T)]
ad<- sample(color, length(leaf2))

# ad<-(c("#e4e4e4" ,"#caff70" ,"#6CA0DC"   ,"#c37dab" ,"#fed65e","#fc766a","#d7c49e","#c83e74","#8ca01f","#e00079","blue","green"))
# while(length(ad)<length(leaf2)){
	
	# ad<-c(ad,ad)
# }
leaf2<-rev(leaf2)

#leaf2<-cluster(p3,eps=mindis*4,minpts=2)


#tree<-root(fitJC$tree, outgroup=outorg)
colo2<-rep("1",nrow(tree[[1]]))
colo3<-c()
cu3<-c()
for(i in 1:length(leaf2)){
	pos<-match(leaf2[[i]],lab)
	pos<-match(pos, tree[[1]][,2])
	colo2[pos]<-ad[i]
	colo3<-c(colo3,ad[i])
	cu3<-c(cu3,as.integer(names(leaf2))[i])
}



lab<-match(lab,coor[,"fin"])
lab<-coor[lab,"nam2"]

 tree$tip.label<-lab
 
 
 
 
selected1<-match(unique(c(sel)),lab2)
selected3<-grep(ooi,lab2)[1]
colo<-rep("1",length(lab))

colo[selected1]<-"dodgerblue"
colo[selected3]<-"olivedrab3"
 
pdf(paste(name,"16S_tree.pdf",sep="_"))
plot(tree, tip.color=colo,edge.color=colo2, cex=0.15)
#plot(tree, tip.color=colo2, cex=0.15)
#nodelabels( cex=0.1, frame="none", col="pink")
nodelabels(,node=cu3,cex=0.3, frame="none", col=colo3)
#tiplabels(cex=0.1)
add.scale.bar()
dev.off()



sel<-match(sel, coor[,"fin"])
fasta<-c()
for(j in 1:length(sel)){
	fasta<-c(fasta, paste(">",gsub("\\..*","",coor[sel[j],"fin"]),sep=""))
	fasta<-c(fasta, as.character(coor[sel[j],"sequence"]))
}
write.table(fasta, file=paste(name,"CopraRNA_selection.fasta",sep="_"), row.names=F, col.names=F, quote=F)



}



selection(maxorgs=20,mindis=mindis,maxdis=maxdis,closeorgs=closeorgs,cluster_thres=1.3,ooi=ooi,name=name,min_size=4, outorg="internal", full_tree=F)
#
#selection(maxorgs=80,mindis=mindis,maxdis=0.02,closeorgs=closeorgs,cluster_thres=1,ooi=ooi,name=ooi,min_size=4, outorg="internal", full_tree=T,wildcard=c("NC_004347","NC_002505","NC_016810","NC_000913","NC_010465","NC_014012","NC_008700.1","NC_011312","NC_008321","NC_021870","NC_008345") )
#cluster_thres lower = more stringent, 1.3 for Cyanobacteria, 0.8 for proteobacteria