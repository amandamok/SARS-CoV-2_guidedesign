##################################################
### helper scripts for compiling results

library(here)

add_column <- function(dat, fname, dat_column, fname_column) {
  # add score from fname to dat
  ## dat: data.frame; contains columns called "start" and "strand
  ## fname: character; file.path to score to be added,
  ### file should include columns: segment, start, strand
  ## dat_column: character; name of column in dat to be added/replaced
  ## fname_column: character; name of column in fname to be pulled
  if(!file.exists(fname)) {
    stop(paste(fname, "does not exist"))
  }
  if("segment" %in% colnames(dat)) {
    column_names <- c("segment", "start", "strand")
  } else {
    column_names <- c("start", "strand")
  }
  score_dat <- read.table(fname, header=T, stringsAsFactors=F, sep="\t")
  row_indices <- prodlim::row.match(dat[, column_names], score_dat[, column_names])
  dat[dat_column] <- score_dat[row_indices, fname_column]
  return(dat)
}

load_abundance <- function(accession="PRJNA616446") {
  # load alignment file of viral abundance dataset
  # assumes align_viral_abundance.R has already been run on default parameters
  ## accession: character ; SRR accession id
  aligned_reads <- system(paste("grep NC_045512v2",
                                file.path(here(), "ref_data/RNA_expression", paste0(accession, "_mapped.sam")),
                                "| grep -v ^@ | cut -f1,3,4"), intern=T)
  aligned_reads <- data.frame(matrix(unlist(strsplit(aligned_reads, split="\t")), ncol=3, byrow=T), stringsAsFactors=F)
  colnames(aligned_reads) <- c("seqID", "rname", "pos")
  aligned_reads$pos <- as.numeric(aligned_reads$pos)
  return(aligned_reads)
}

load_coverage <- function(id="PRJNA616446", binSize=300) {
  # load coverage file of viral abundance (generated by bedtools genomecov)
  ## id: character ; header for coverage file
  ## binSize: integer ; bin size to take median coverage over
  # read in data
  id_cov <- read.table(file.path(here(), "ref_data/RNA_expression", paste0(id, "_mapped.cov")),
                       header=F, stringsAsFactors=F, col.names=c("genome", "pos", "coverage"))
  # break into bins
  id_cov$bin <- cut(id_cov$pos, breaks=ceiling(max(id_cov$pos)/binSize), labels=F)
  # take median coverage per bin
  id_cov <- aggregate(coverage~bin, data=id_cov, FUN=median)
  # rescale position to genomic coordinates
  id_cov$bin <- (id_cov$bin-1)*binSize + binSize/2
  return(id_cov)
}

plot_diagnostic <- function(dat, abundance_dat, filter=NULL, density=T, jitter_x=0, jitter_y=0, alpha=1,
                            var1, var1_name, var1_desc, var2, var2_name, var2_desc, var3, var3_name, var3_desc) {
  # generate diagnostic plot for filtered spacers
  ## dat: data.frame ; compiled scores for windows
  ## abundance_dat: data.frame ; output from load_abundance()
  ## filter: character ; subtitle to describe filter applied to windows
  ## density: logical ; plot univariate densities (instead of histograms)
  ## jitter_x: numeric ; amount of x-axis jitter to add on scatterplot
  ## jitter_y: numeric ; amount of y-axis jitter to add on scatterplot
  ## alpha: numeric ; alpha for scatter plot
  ## var1: string; column name in dat for scatterplot x-axis
  ## var1_name: string; for scatterplot xlab() and univariate ggtitle()
  ## var1_desc: string; for univariate xlab()
  ## var2: string; column name in dat for scatterplot y-axis
  ## var1_name: string; for scatterplot ylab() and univariate ggtitle()
  ## var1_desc: string; for univariate xlab()
  ## var3: string; column name in dat for scatterplot color
  ## var1_name: string; legend label and univariate ggtitle()
  ## var1_desc: string; for univariate xlab()
  # scatterplot
  plot_scatter <- ggplot(dat, aes_string(x=var1, y=var2, col=var3)) +
    geom_jitter(width=jitter_x, height=jitter_y, alpha=alpha) +
    theme_bw() + xlab(var1_name) + ylab(var2_name) +
    scale_color_gradient2(high="red", low="blue", mid="grey",
                          midpoint=mean(dat[, var3]), name=var3_name)
  if(is.null(filter)) {
    plot_scatter <- plot_scatter + ggtitle(paste("Scores for all spacers, n =", nrow(dat)))
    subtitle="all spacers"
  } else {
    plot_scatter <- plot_scatter + ggtitle(paste("Scores for filtered spacers, n =", nrow(dat)),
                                           subtitle=filter)
    subtitle <- "filtered spacers"
  }
  # univariate plots
  plot_var1 <- ggplot(dat, aes_string(var1)) + theme_bw() + ggtitle(var1_name, subtitle=subtitle) + xlab(var1_desc)
  plot_var2 <- ggplot(dat, aes_string(var2)) + theme_bw() + ggtitle(var2_name, subtitle=subtitle) + xlab(var2_desc)
  plot_var3 <- ggplot(dat, aes_string(var3)) + theme_bw() + ggtitle(var3_name, subtitle=subtitle) + xlab(var3_desc)
  if(density) {
    plot_var1 <- plot_var1 + geom_density(kernel="gaussian", fill=3, col=3)
    plot_var2 <- plot_var2 + geom_density(kernel="gaussian", fill=4, col=4)
    plot_var3 <- plot_var3 + geom_density(kernel="gaussian", fill=5, col=5)
  } else {
    plot_var1 <- plot_var1 + geom_histogram(binwidth=0.05, fill=2, col=2) + ylab("# spacers")
    plot_var2 <- plot_var2 + geom_histogram(binwidth=0.15, fill=3, col=3) + ylab("# spacers")
    plot_var3 <- plot_var3 + geom_histogram(binwidth=1, fill=4, col=4) + ylab("# spacers")
  }
  # guide position / viral abundance plot
  genome_breaks <- seq(from=1, to=30000, by=300)
  # axis_scale <- ceiling(max(summary(cut(abundance_dat$pos, breaks=genome_breaks))) /
  #                         max(summary(cut(dat$start, breaks=genome_breaks))))
  # abundance_summary <- data.frame(bin=genome_breaks, # [-length(genome_breaks)]
  #                                 coverage=summary(cut(abundance_dat$pos, breaks=genome_breaks))/axis_scale)
  axis_scale <- max(abundance_dat$coverage)/max(summary(cut(dat$start, breaks=genome_breaks)))
  abundance_dat$coverage <- abundance_dat$coverage / axis_scale
  plot_position <- ggplot() +
    geom_histogram(data=dat, aes(start), binwidth=300, fill=2, col=2, alpha=0.5) + xlim(0, 30000) +
    geom_area(data=abundance_dat, aes(x=bin, y=coverage), fill=1, col=1, alpha=0.2) +
    scale_y_continuous(name="guide", sec.axis=sec_axis(~(axis_scale)*., name="virus")) +
    theme_bw() + ggtitle("Genomic position", subtitle=subtitle) + xlab("position") + ylab("# spacers") +
    theme(axis.title.y=element_text(color=1), axis.title.y.left = element_text(color=2))
  plot_scatter + (plot_position / plot_var1 / plot_var2 / plot_var3)
}

plot_summary <- function(dat_list, variable, var_name, filter_names, density=T, binwidth=0.1) {
  # generate plots of variable over subsets
  ## dat_list: list of data.frames
  ## variable: character; column name in all data.frames in dat_list
  ## var_name: character; for ggtitle()
  ## filter_names: character vector; filter descriptioms for ggtitle(subtitle)
  ## density: logical; whether to use geom_density() or geom_histogram()
  ## binwidth: numeric; binwidth for geom_histogram()
  plot_list <- list()
  for(x in seq_along(dat_list)) {
    plot_list[[x]] <- ggplot(dat_list[[x]], aes_string(variable)) + theme_bw() + xlab(var_name)
    if(density) {
      plot_list[[x]] <- plot_list[[x]] + geom_density(fill=x, col=x)
    } else {
      plot_list[[x]] <- plot_list[[x]] + geom_histogram(fill=x, col=x, binwidth=binwidth)
    }
    if(x==1) {
      plot_list[[x]] <- plot_list[[x]] + ggtitle(var_name, filter_names[x])
    } else {
      plot_list[[x]] <- plot_list[[x]] + ggtitle(" ", filter_names[x])
    }
  }
}