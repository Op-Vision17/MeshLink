import '../repositories/mesh_repository.dart';

class ToggleMeshServiceUseCase {
  final MeshRepository repository;

  ToggleMeshServiceUseCase(this.repository);

  Future<bool> start() async {
    return await repository.startDiscovery();
  }

  Future<bool> stop() async {
    return await repository.stopDiscovery();
  }
}
