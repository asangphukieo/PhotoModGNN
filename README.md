# PhotoModGNN v.2.0 (standalone version)
PhotoModGNN for visualizing genome neighborhood as a network

<B>Input</B><br>
1 gene neighborhood list (SR1_synteny_table.txt)<br>
2 gene homolog list (SR1_cluster_table.txt)<br>
3 coding sequence of neighboring genes (protein_fasta.txt)<br>
4 16s rRNA of observed genomes<br>
<br>
These inputs can be generated by GLASSgo_postprocessing_8_modi.r<br>
<br>
<br>
<B>Run</B><br>
1 Install conda build_tree package and activate<br>
  "conda env create --name build_tree --file build_tree.yml"<br>
  "conda activate build_tree"<br>
  <br>
2 download uniprot database and extract GO terms and protein sequences (ftp://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/complete/uniprot_sprot.dat.gz) <br>
  "python extract_GO_from_uniprot_DAT.py uniprot_sprot.dat >uniprot_GO2019.txt"<br>
  "python extract_fasta_from_uniprot_DAT.py uniprot_sprot.dat >uniprot.fasta"<br>
<br>
3 calculate genome neighborhood conservation score and specify taxonomy level for color labeling (e.g. 'genus', 'family', 'order')<br>
  "python run.py ./test_input/SR1_synteny_table.txt ./test_input/SR1_cluster_table.txt ../../../input/db/uniprot.fasta 'genus' ./test_input/16s_GenBank.fasta ./test_input/protein_fasta.txt"<br>
  <br>
  output<br>
  1 node2edge.cy <br>
  2 mapping.q <br>
  3 mapping.n<br>
  <br>
4 build js file<br>
  "python read_output_network_photomod_v0_2.py node2edge.cy mapping.q mapping.n test.js"<br>
  <br>
5 open file "result_network_photomod.html" to see the output<br>

![Screenshot](https://github.com/asangphukieo/PhotoModGNN/blob/master/slid_pic.svg)

