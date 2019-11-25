from build_tree_v0_6 import *
import sys
import subprocess
from subprocess import call
from ete3 import Tree, TextFace, TreeStyle

path_to_uniprot_fasta=sys.argv[3]

def my_layout(node):
	try:
		value = refseq_color[node.name]
		if value[0] is not None:

			node.img_style["size"] = 0
			node.img_style["bgcolor"] = value[0]
			node.img_style["line_type"] = 1

			if node.is_leaf():
				color = 'red'
			if color:
				name_face = TextFace(value[1], fgcolor='black', fsize=10)
				node.add_face(name_face, column=0, position='branch-right')

		else:
			node.img_style["size"] = 0
	except KeyError:
		print('except error')

def map_blastout_2_nID(blastout,synteny_db,output):
	conn = sqlite3.connect(synteny_db)
	c = conn.cursor()
	w2file=open(output,'w')
	for i in open(blastout):
		i=i.rstrip()
		if i != '':
			col=i.split('\t') #ABC2405_nqRV	Q5WFC0,NA,UPF0637 protein ABC2405 ,NA	100.0
			#print(col[0])
			try:
				c.execute("SELECT cluster_id,genes FROM cluster WHERE genes='"+str(col[0])+"'")
				result1 = c.fetchall()
				w2file.write('n.'+str(result1[0][0])+','+str(col[0])+','+col[1]+','+col[2]+'\n')
			except sqlite3.OperationalError:
				print('Seq ID',str(col[0]),'not found.')
	w2file.close()

def make_phylo_tree_figure(fasta_16s,mapping_query,tax_level):
	cmd='cut -f4,6,7 -d"," '+mapping_query+'| sort -u -k2,2 -t","'
	ps=Popen(cmd,shell=True,stdin=PIPE, stdout=PIPE, stderr=STDOUT, close_fds=True,encoding='utf8')
	output = ps.stdout.read().split('\n')
	dict_taxcolor={}
	for j in output:
		if j != '':
			j=j.split(',')
			dict_taxcolor[j[1]]=j[0]+','+j[2] # 'tax_id': 'refseqID, color code'
	read_16s=open(fasta_16s,'r')
	read_16s_r=read_16s.read()
	read_16s.close()
	read_16s_r=read_16s_r.split('>')
	tree16s=''
	refseq_color={}
	for i in dict_taxcolor:
		refseqID=dict_taxcolor[i].split(',')[0]
		for k in read_16s_r:
			if refseqID in k:
				tree16s+='>'+k

		taxo_rank=call_taxonomy(dict_taxcolor[i].split(',')[0].split('.')[0],tax_level) # return: [0]selected_taxID, [1]tax_ranking, [2]org_name
		
		refseq_color[dict_taxcolor[i].split(',')[0]] = [dict_taxcolor[i].split(',')[1], taxo_rank[1] ]
	w=open('input_16s_tree.fasta','w')
	w.write(tree16s)
	w.close()
	make_multiple_seq_align("input_16s_tree.fasta")
	make_phylo_fasttree('input_16s_tree.phy','input_16s_tree.nw')

	return refseq_color

def make_tree_figure(nw_file):
	## build tree ##
	nw_format=open(nw_file)
	nw_read=nw_format.read()
	nw_format.close()
	print(nw_read)
	t = Tree(nw_read, format=1)
	ts = TreeStyle()
	ts.show_leaf_name = False
	ts.show_scale = False
	ts.show_leaf_name = False
	ts.show_scale = False
	t.render("label_tree.png", my_layout,tree_style=ts,dpi=150, w=600)

neighboring_protein_fasta=sys.argv[6]
print('synteny file =>',sys.argv[1])
print('protein cluster file =>',sys.argv[2])
print('path to Uniport file =>',sys.argv[3])
print('taxonomy label level =>',sys.argv[4])
print('16sRNA file =>',sys.argv[5])
print('Gene neighbor file =>',neighboring_protein_fasta)


remove_duplication_seq(sys.argv[5],'16s_u.fasta')
synteny2DB(sys.argv[1],sys.argv[2],'16s_u.fasta') #synteny table , cluster table
calculate_Phylo_score('synteny.db',3,0) #database name , number of conserved genomes cutoff, weight score for network relationship
make_network_input_2(sys.argv[2], sys.argv[1], 'SR1_nb.out', 'False', sys.argv[4]) #taxonomy_level: tax_level follows ncbi taxonomy: e.g. superkingdom, phylum, order, family, genus, species

refseq_color=make_phylo_tree_figure(sys.argv[5],'mapping.q',sys.argv[4])
make_tree_figure('input_16s_tree.nw')            

## get ouput in Phylo_score.tab
## get ouput in SR1_nb.out

convert_node2edge_weight('SR1_nb.out','Phylo_score.tab','node2edge.csv')
call('sed s/",c."/",n."/g node2edge.csv > node2edge.cy',shell=True) #** change c. to n. label

## need to install diamond 'conda install -c bioconda diamond'
print('Running diamond blastp...')
call('diamond blastp -d '+path_to_uniprot_fasta+' -q '+neighboring_protein_fasta+' -e 0.001 --max-target-seqs 1 --query-cover 0.8 --subject-cover 0.8 --outfmt 6 qseqid salltitles pident > diamond.blastout',shell=True) 
print('Finish! diamond blastp')

map_blastout_2_nID('diamond.blastout','synteny.db','mapping.n')

#final output
#[1] mapping.n
#[2] mapping.q
#[3] node2edge.cy

#usage: python ../script/run.py SR1_synteny_table.txt SR1_cluster_table.txt ../input/db/uniprot.fasta 'genus' 16s_GenBank.fasta

#python run.py ./test_input/SR1_synteny_table.txt ./test_input/SR1_cluster_table.txt uniprot.fasta 'genus' ./test_input/16s_GenBank.fasta ./test_input/protein_fasta.txt



