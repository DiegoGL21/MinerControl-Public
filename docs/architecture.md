# Arquitectura de Miner Control

Miner Control está desarrollado con Godot 4.7.2 y GDScript. La aplicación utiliza una arquitectura basada en escenas para componer el flujo del juego y scripts especializados para controlar cada sistema.

## Organización general

- **Jugador:** concentra movimiento, orientación, salto cargado y estados de interacción.
- **Nivel 1:** está dividido internamente en tres fases conectadas que forman un recorrido vertical continuo.
- **Peligros:** la lava ascendente coordina presión ambiental, pérdida de vidas y reaparición.
- **Plataformas:** combina superficies fijas y plataformas móviles para construir el recorrido.
- **Minerales:** los objetos coleccionables mantienen identidad persistente y alimentan el progreso del nivel.
- **HUD:** presenta vidas, minerales y retroalimentación relevante durante la partida.
- **Pausa:** permite detener y reanudar la sesión, guardar el progreso o volver al menú.
- **Guardado:** conserva el progreso necesario para continuar una partida desde el menú principal.

## Alcance de esta publicación

La carpeta `src` contiene solamente una selección representativa de scripts. Las escenas, recursos de producción y archivos artísticos no forman parte del código fuente público. La demo compilada se distribuye por separado en `release`.
