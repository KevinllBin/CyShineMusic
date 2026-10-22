enum SearchCategory {
  all('全部'),
  artists('艺人'),
  songs('歌曲'),
  playlists('歌单'),
  albums('专辑');

  const SearchCategory(this.label);
  final String label;
}
